---
title: Конфигурирование инфраструктуры в виде кода
permalink: nodejs/100_basic/50_iac.html
---

{% filesused title="Файлы, упомянутые в главе" %}
- .helm/templates/deployment.yaml
- .helm/templates/ingress.yaml
- .helm/templates/service.yaml
- .helm/values.yaml
{% endfilesused %}

Ранее мы уже описали инфраструктуру в виде объектов Kubernetes. Шаблонизируем эту конфигурацию с помощью [Helm](https://helm.sh/), его движок встроен в werf. Помимо этого, werf предоставляет возможности работы с секретными значениями, а также дополнительные Go-шаблоны для интеграции собранных образов.

В этой главе мы научимся описывать Helm-шаблоны, используя возможности werf, а также освоим встроенные инструменты отладки. **Эта глава в значительной мере теоретическая, но знания, которые здесь даны пригодятся в реальной практике.**

{% offtopic title="Что делать, если вы не работали с Helm?" %}

Не будем вдаваться в подробности [разработки YAML-манифестов с помощью Helm для Kubernetes](https://habr.com/ru/company/flant/blog/423239/). Если у вас есть вопросы о том, как именно описываются объекты Kubernetes, советуем посетить страницы документации Kubernetes о [концепциях](https://kubernetes.io/ru/docs/concepts/) и документацию Helm по [разработке шаблонов](https://helm.sh/docs/chart_template_guide/).

В первое время работа с Helm и конфигурацией для Kubernetes может быть очень сложной из-за нелепых мелочей вроде опечаток и пропущенных пробелов. Если вы только начали осваивать эти технологии — постарайтесь найти наставника, который поможет преодолеть эти сложности и посмотрит на ваши исходники сторонним взглядом.

В случае затруднений убедитесь, что вы:

- понимаете, как работает [indent](https://helm.sh/docs/chart_template_guide/function_list/#indent);
- понимаете, что такое [конструкция tuple](https://helm.sh/docs/chart_template_guide/control_structures/);
- понимаете, как Helm работает с хэш-массивами;
- очень внимательно следите за пробелами в YAML.

{% endofftopic %}

## Подстановка переменных

В описании Deployment, Ingress и Service используется значение `basicapp` — лучше заменить его переменной. Воспользуемся для этого переменной с именем чарта `.Chart.Name`. Например, было:

{% snippetcut name=".helm/templates/deployment.yaml" url="https://github.com/werf/werf-guides/blob/master/examples/nodejs/020_optimize_build/.helm/templates/deployment.yaml" %}
{% raw %}
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: basicapp
spec:
  selector:
    matchLabels:
      app: basicapp
```
{% endraw %}
{% endsnippetcut %}

Стало:

{% snippetcut name=".helm/templates/deployment.yaml" url="https://github.com/werf/werf-guides/blob/master/examples/nodejs/025_iac/.helm/templates/deployment.yaml" %}
{% raw %}
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
spec:
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
```
{% endraw %}
{% endsnippetcut %}

## Конфигурирование шаблона

В реальной практике одно и то же приложение выкатывается на разные стенды (production, test, staging и т.п.). И для разных стендов зачастую нужно использовать разные значения.

В werf для этого существует три механики:

1. Подстановка значений из `values.yaml` по аналогии с Helm.
2. Проброс значений через аргумент `--set` при работе в CLI-режиме, по аналогии с Helm.
3. Подстановка секретных значений из `secret-values.yaml`.

### Использование values.yaml

Создадим файл `values.yaml` и будем там хранить имя файла базы данных и скорректируем объект Deployment. Острой необходимости в этом нет, но это важный инструмент, без которого не возможна разработка реальных приложений.

{% snippetcut name=".helm/values.yaml" url="#" %}
{% raw %}
```yaml
app:
  sqlite_file:
    _default: "app.db"
    production: "app.db"
    testing: "app.db"
```
{% endraw %}
{% endsnippetcut %}

Нужные значения подставляются в helm-шаблоны:

{% snippetcut name=".helm/templates/deployment.yaml" url="#" %}
{% raw %}
```yaml
        env:
        - name: "SQLITE_FILE"
          value: {{ pluck .Values.global.env .Values.app.sqlite_file | first | default .Values.app.sqlite_file._default | quote }}
```
{% endraw %}
{% endsnippetcut %}

Helm узнаёт о том, значения для какого из стендов использовать на основании переменной `.Values.global.env`. Позже, в главе "Работа с инфраструктурой", мы рассмотрим, как значение этой переменной автоматически подставляется CI-системой. Вручную значение можно задать при запуске `converge` примерно так:

```bash
werf converge --repo registry.mydomain.io/werf-guided-project --env production
```

### Проброс значений через --set

Второй вариант подразумевает **задание переменных через CLI**. Например, в `converge` можно передать нужное значение 

```bash
werf converge --repo registry.mydomain.io/werf-guided-project --set "global.myvariable=somevalue"
```

И можно будет использовать это значение в шаблонах:

{% snippetcut name=".helm/templates/deployment.yaml" url="#" %}
{% raw %}
```yaml
        env:
        - name: "SQLITE_FILE"
          value: {{ .Values.global.myvariable | quote }}
```
{% endraw %}
{% endsnippetcut %}

Этот вариант удобен для проброса, например, имени домена для каждого окружения. К этому вопросу мы вернёмся, когда будем выстраивать CI-процесс в главе "Работа с инфраструктурой".

### Подстановка секретных значений 

<a name="secret-values-yaml" />Отдельная проблема — **хранение и задание секретных переменных**, например, учётных данных аутентификации для сторонних сервисов, API-ключей и т.п.

Так как werf рассматривает Git как единственный источник правды, правильно хранить секретные переменные там же. Чтобы делать это корректно, мы [храним данные в шифрованном виде]({{ site.docsurl }}/documentation/reference/deploy_process/working_with_secrets.html). Подстановка значений из этого файла происходит при рендере шаблона, который также запускается при деплое.

Чтобы воспользоваться секретными переменными:

* [сгенерируйте ключ]({{ site.docsurl }}/documentation/cli/management/helm/secret/generate_secret_key.html) (`werf helm secret generate-secret-key`);
* определите ключ в переменных окружения для приложения, в текущей сессии консоли (например, `export WERF_SECRET_KEY=634f76ead513e5959d0e03a992372b8e`);
* пропишите полученный ключ в `Variables` для вашего репозитория в GitLab (раздел `Settings` → `CI/CD`), название переменной должно быть­`WERF_SECRET_KEY`:

![](/applications_guide_ru/images/applications-guide/020-werf-secret-key-in-gitlab.png)

После этого можно задать секретные переменные `access_key` и `secret_key`, например, для работы с S3. Зайдите в режим редактирования секретных значений:

```bash
$ werf helm secret values edit .helm/secret-values.yaml
```

Откроется консольный текстовый редактор с данными в расшифованном виде:

{% snippetcut name=".helm/secret-values.yaml в расшифрованном виде" url="#" ignore-tests %}
```yaml
app:
  s3:
    access_key:
      _default: bNGXXCF1GF
    secret_key:
      _default: zpThy4kGeqMNSuF2gyw48cOKJMvZqtrTswAQ
```
{% endsnippetcut %}

После сохранения значения в файле зашифруются и примут примерно такой вид:

{% snippetcut name=".helm/secret-values.yaml в зашифрованном виде" url="#" ignore-tests %}
```yaml
app:
  s3:
    access_key:
      _default: 1000f82ff86a5d766b9895b276032928c7e4ff2eeb20cab05f013e5fe61d21301427
    secret_key:
      _default: 1000bee1b42b57e39a9cfaca7ea047de03043c45e39901b8974c5a1f275b98fd0ac2c72efbc62b06cad653ebc4195b680370dc9c04e88a8182a874db286d8360def6
```
{% endsnippetcut %}

<div id="go-forth-button">
    <go-forth url="210_cluster.html" label="Сборка" framework="{{ page.label_framework }}" ci="{{ page.label_ci }}" guide-code="{{ page.guide_code }}" base-url="{{ site.baseurl }}"></go-forth>
</div>