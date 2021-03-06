module Jekyll
  module Expandonclick
    class ExpandonclickTag < Liquid::Block
      @@DEFAULTS = {
          :id => 'expandableblock',
      }

      def self.DEFAULTS
        return @@DEFAULTS
      end

      def initialize(tag_name, markup, tokens)
        super

        @config = {}
        override_config(@@DEFAULTS)

        params = markup.scan /([a-z]+)\=\"(.+?)\"/
        if params.size > 0
          config = {}
          params.each do |param|
            config[param[0].to_sym] = param[1]
          end
          override_config(config)
        end
      end

      def override_config(config)
        config.each{ |key,value| @config[key] = value }
      end

      def render(context)
        content = super

        rendered_content = Jekyll::Converters::Markdown::KramdownParser.new(Jekyll.configuration()).convert(content)

        %Q(
<div class="expand_columns_content" id="#{@config[:id]}">
#{rendered_content}
</div>
        )
      end
    end
  end
end

Liquid::Template.register_tag('expandonclick', Jekyll::Expandonclick::ExpandonclickTag)
