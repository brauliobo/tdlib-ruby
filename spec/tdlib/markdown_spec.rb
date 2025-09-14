require 'spec_helper'

describe TD::Markdown do
  let(:client) { double('TD::Client') }

  describe '.parse' do
    context 'with nil text' do
      it 'returns empty formatted text' do
        result = TD::Markdown.parse(client, nil)
        
        expect(result).to be_a(TD::Types::FormattedText)
        expect(result.text).to eq('')
        expect(result.entities).to eq([])
      end
    end

    context 'with empty text' do
      before do
        allow(client).to receive(:parse_text_entities).and_return(
          double(value!: TD::Types::FormattedText.new(text: '', entities: []))
        )
      end

      it 'returns empty formatted text' do
        result = TD::Markdown.parse(client, '')
        
        expect(result).to be_a(TD::Types::FormattedText)
        expect(result.text).to eq('')
        expect(result.entities).to eq([])
      end
    end

    context 'when TDLib parsing succeeds' do
      let(:formatted_text) do
        TD::Types::FormattedText.new(
          text: 'Hello world',
          entities: [
            TD::Types::TextEntity.new(
              offset: 0,
              length: 5,
              type: TD::Types::TextEntityType::Bold.new
            )
          ]
        )
      end

      before do
        allow(client).to receive(:parse_text_entities).and_return(
          double(value!: formatted_text)
        )
      end

      it 'uses TDLib parser with correct parameters' do
        expect(client).to receive(:parse_text_entities).with(
          text: '*Hello* world',
          parse_mode: kind_of(TD::Types::TextParseMode::Markdown)
        )

        TD::Markdown.parse(client, '*Hello* world')
      end

      it 'returns the TDLib parsed result' do
        result = TD::Markdown.parse(client, '*Hello* world')
        expect(result).to eq(formatted_text)
      end
    end

    context 'when TDLib parsing fails' do
      before do
        allow(client).to receive(:parse_text_entities).and_raise(StandardError.new('TDLib error'))
        allow(STDERR).to receive(:puts)
      end

      it 'falls back to local parser' do
        result = TD::Markdown.parse(client, '*bold* text')
        
        expect(result).to be_a(TD::Types::FormattedText)
        expect(result.text).to eq('bold text')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Bold)
      end

      it 'logs error in debug mode' do
        ENV['DEBUG'] = '1'
        expect(STDERR).to receive(:puts).with(/md_parse_error/)
        
        TD::Markdown.parse(client, '*bold* text')
        
        ENV.delete('DEBUG')
      end
    end
  end

  describe 'fallback parser' do
    before do
      allow(client).to receive(:parse_text_entities).and_raise(StandardError.new('TDLib error'))
      allow(STDERR).to receive(:puts)
    end

    context 'with bold text' do
      it 'parses single bold segment' do
        result = TD::Markdown.parse(client, '*bold*')
        
        expect(result.text).to eq('bold')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.offset).to eq(0)
        expect(result.entities.first.length).to eq(4)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Bold)
      end

      it 'parses bold text with surrounding text' do
        result = TD::Markdown.parse(client, 'Hello *world* test')
        
        expect(result.text).to eq('Hello world test')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.offset).to eq(6)
        expect(result.entities.first.length).to eq(5)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Bold)
      end

      it 'parses multiple bold segments' do
        result = TD::Markdown.parse(client, '*first* and *second*')
        
        expect(result.text).to eq('first and second')
        expect(result.entities.length).to eq(2)
        
        expect(result.entities[0].offset).to eq(0)
        expect(result.entities[0].length).to eq(5)
        expect(result.entities[0].type).to be_a(TD::Types::TextEntityType::Bold)
        
        expect(result.entities[1].offset).to eq(10)
        expect(result.entities[1].length).to eq(6)
        expect(result.entities[1].type).to be_a(TD::Types::TextEntityType::Bold)
      end
    end

    context 'with italic text' do
      it 'parses single italic segment' do
        result = TD::Markdown.parse(client, '_italic_')
        
        expect(result.text).to eq('italic')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.offset).to eq(0)
        expect(result.entities.first.length).to eq(6)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Italic)
      end

      it 'parses italic text with surrounding text' do
        result = TD::Markdown.parse(client, 'Hello _world_ test')
        
        expect(result.text).to eq('Hello world test')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.offset).to eq(6)
        expect(result.entities.first.length).to eq(5)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Italic)
      end
    end

    context 'with mixed formatting' do
      it 'parses both bold and italic' do
        result = TD::Markdown.parse(client, '*bold* and _italic_')
        
        expect(result.text).to eq('bold and italic')
        expect(result.entities.length).to eq(2)
        
        expect(result.entities[0].type).to be_a(TD::Types::TextEntityType::Bold)
        expect(result.entities[1].type).to be_a(TD::Types::TextEntityType::Italic)
      end
    end

    context 'with no formatting' do
      it 'returns plain text with no entities' do
        result = TD::Markdown.parse(client, 'plain text')
        
        expect(result.text).to eq('plain text')
        expect(result.entities).to eq([])
      end
    end

    context 'with UTF-16 characters' do
      it 'handles emoji correctly' do
        result = TD::Markdown.parse(client, '👋 *hello* 🌍')
        
        expect(result.text).to eq('👋 hello 🌍')
        expect(result.entities.length).to eq(1)
        expect(result.entities.first.offset).to eq(3) # emoji takes 2 UTF-16 units + space = 3
        expect(result.entities.first.length).to eq(5)
        expect(result.entities.first.type).to be_a(TD::Types::TextEntityType::Bold)
      end
    end
  end

  describe '.utf16_len' do
    it 'counts regular characters as 1' do
      expect(TD::Markdown.send(:utf16_len, 'hello')).to eq(5)
    end

    it 'counts emoji as 2' do
      expect(TD::Markdown.send(:utf16_len, '👋')).to eq(2)
    end

    it 'handles mixed content' do
      expect(TD::Markdown.send(:utf16_len, 'hi👋')).to eq(4)
    end
  end
end
