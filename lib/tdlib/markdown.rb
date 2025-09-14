module TD
  # Converts Telegram-Markdown-V2 into TD::Types::FormattedText.
  #
  # It first tries TDLib's own parser; if that fails (older TDLib build),
  # it falls back to a lightweight local parser that supports *bold* and _italic_.
  class Markdown
    class << self
      def parse(client, text)
        return TD::Types::FormattedText.new(text: '', entities: []) if text.nil?

        client.parse_text_entities(
          text: text.to_s,
          parse_mode: TD::Types::TextParseMode::Markdown.new(version: 2),
        ).value!
      rescue => e
        STDERR.puts "md_parse_error: #{e.class}: #{e.message} -- #{text.inspect}" if ENV['DEBUG']
        fallback(text)
      end

      private

      def fallback(text)
        plain = ''.dup
        entities = []
        pos_utf16 = 0
        
        # Split text while preserving delimiters and process each part
        parts = text.split(/(\*[^*]+\*|_[^_]+_)/)
        
        parts.each do |part|
          if part.match?(/^\*[^*]+\*$/) || part.match?(/^_[^_]+_$/)
            # This is a formatted segment
            content = part[1...-1] # strip markers
            len = utf16_len(content)
            entities << TD::Types::TextEntity.new(
              offset: pos_utf16,
              length: len,
              type: part.start_with?('*') ? TD::Types::TextEntityType::Bold.new : TD::Types::TextEntityType::Italic.new,
            )
            plain << content
            pos_utf16 += len
          else
            # This is plain text
            plain << part
            pos_utf16 += utf16_len(part)
          end
        end

        TD::Types::FormattedText.new text: plain, entities: entities
      end

      def utf16_len(str)
        str.each_char.sum { |c| c.ord > 0xFFFF ? 2 : 1 }
      end
    end
  end
end
