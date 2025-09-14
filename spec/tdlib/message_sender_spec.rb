require 'spec_helper'

RSpec.describe TD::MessageSender do
  let(:mock_client) { double('TD::Client') }
  let(:message_sender) { TD::MessageSender.new(mock_client) }
  let(:chat_id) { 123456 }
  let(:message_id) { 789012 }
  let(:test_text) { 'Test message' }

  before do
    # Mock the client.on method for message tracking
    allow(mock_client).to receive(:on)
    
    # Mock the logging method
    allow(message_sender).to receive(:dlog)
    
    # Mock the markdown parser
    allow(message_sender).to receive(:parse_markdown_text).and_return(
      double('formatted_text', text: test_text, entities: [])
    )
  end

  describe '#send_text' do
    let(:mock_result) { double('message', id: message_id, text: test_text) }
    let(:mock_send_result) { double('send_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:send_message).and_return(mock_send_result)
    end

    context 'without reply_to' do
      it 'sends text message successfully' do
        result = message_sender.send_text(chat_id, test_text)
        
        expect(result).to eq({message_id: 0, text: "Test message"})
        expect(mock_client).to have_received(:send_message) do |args|
          expect(args[:chat_id]).to eq(chat_id)
          expect(args[:reply_to]).to be_nil
        end
      end
    end

    context 'with reply_to' do
      let(:reply_message_id) { 555666 }
      
      it 'sends text message with reply_to' do
        result = message_sender.send_text(chat_id, test_text, reply_to: reply_message_id)
        
        expect(result).to eq({message_id: 0, text: "Test message"})
        expect(mock_client).to have_received(:send_message) do |args|
          expect(args[:chat_id]).to eq(chat_id)
          expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
          expect(args[:reply_to].message_id).to eq(reply_message_id)
        end
      end
    end

    context 'with custom parse_mode' do
      it 'uses specified parse mode' do
        message_sender.send_text(chat_id, test_text, parse_mode: 'HTML')
        
        expect(message_sender).to have_received(:parse_markdown_text).with(test_text, 'HTML')
      end
    end
  end

  describe '#edit_message' do
    let(:mock_result) { double('edited_message', id: message_id) }
    let(:mock_edit_result) { double('edit_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:edit_message_text).and_return(mock_edit_result)
    end

    it 'edits message successfully' do
      result = message_sender.edit_message(chat_id, message_id, test_text)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:edit_message_text) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:message_id]).to eq(message_id)
        expect(args[:reply_markup]).to be_nil
        expect(args[:input_message_content]).to be_a(TD::Types::InputMessageContent::Text)
      end
    end

    it 'handles edit failures gracefully' do
      allow(mock_edit_result).to receive(:value).and_return(nil)
      
      result = message_sender.edit_message(chat_id, message_id, test_text)
      
      expect(result).to be_nil
    end

    it 'handles exceptions gracefully' do
      allow(mock_client).to receive(:edit_message_text).and_raise(StandardError, 'edit failed')
      
      result = message_sender.edit_message(chat_id, message_id, test_text)
      
      expect(result).to be_nil
    end
  end

  describe '#delete_message' do
    let(:mock_result) { double('delete_result', ok: true) }
    let(:mock_delete_result) { double('delete_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:delete_messages).and_return(mock_delete_result)
    end

    it 'deletes message successfully' do
      result = message_sender.delete_message_public(chat_id, message_id)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:delete_messages) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:message_ids]).to eq([message_id])
        expect(args[:revoke]).to be true
      end
    end

    it 'handles delete failures gracefully' do
      allow(mock_delete_result).to receive(:value).and_return(nil)
      
      result = message_sender.delete_message_public(chat_id, message_id)
      
      expect(result).to be_nil
    end

    it 'handles exceptions gracefully' do
      allow(mock_client).to receive(:delete_messages).and_raise(StandardError, 'delete failed')
      
      result = message_sender.delete_message_public(chat_id, message_id)
      
      expect(result).to be_nil
    end
  end

  describe '#send_video' do
    let(:video_path) { '/path/to/video.mp4' }
    let(:caption) { 'Video caption' }
    let(:mock_result) { double('message', id: message_id) }
    let(:mock_send_result) { double('send_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:send_message).and_return(mock_send_result)
      allow(message_sender).to receive(:extract_local_path).and_return(video_path)
    end

    it 'sends video with reply_to' do
      reply_message_id = 111222
      
      result = message_sender.send_video(chat_id, caption, video: video_path, reply_to: reply_message_id)
      
      expect(result).to eq({message_id: 0, text: "Video caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
        expect(args[:reply_to].message_id).to eq(reply_message_id)
      end
    end

    it 'sends video without reply_to' do
      result = message_sender.send_video(chat_id, caption, video: video_path)
      
      expect(result).to eq({message_id: 0, text: "Video caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:reply_to]).to be_nil
      end
    end
  end

  describe '#send_document' do
    let(:document_path) { '/path/to/document.pdf' }
    let(:caption) { 'Document caption' }
    let(:mock_result) { double('message', id: message_id) }
    let(:mock_send_result) { double('send_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:send_message).and_return(mock_send_result)
      allow(message_sender).to receive(:extract_local_path).and_return(document_path)
    end

    it 'sends document with reply_to' do
      reply_message_id = 333444
      
      result = message_sender.send_document(chat_id, caption, document: document_path, reply_to: reply_message_id)
      
      expect(result).to eq({message_id: 0, text: "Document caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
        expect(args[:reply_to].message_id).to eq(reply_message_id)
      end
    end

    it 'sends document without reply_to' do
      result = message_sender.send_document(chat_id, caption, document: document_path)
      
      expect(result).to eq({message_id: 0, text: "Document caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:reply_to]).to be_nil
      end
    end
  end

  describe '#send_audio' do
    let(:audio_path) { '/path/to/audio.mp3' }
    let(:caption) { 'Audio caption' }
    let(:mock_result) { double('message', id: message_id) }
    let(:mock_send_result) { double('send_result', value: mock_result) }

    before do
      allow(mock_client).to receive(:send_message).and_return(mock_send_result)
      allow(message_sender).to receive(:extract_local_path).and_return(audio_path)
    end

    it 'sends audio with reply_to' do
      reply_message_id = 333444
      
      result = message_sender.send_audio(chat_id, caption, audio: audio_path, reply_to: reply_message_id)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
        expect(args[:reply_to].message_id).to eq(reply_message_id)
        expect(args[:input_message_content]).to be_a(TD::Types::InputMessageContent::Audio)
      end
    end

    it 'sends audio without reply_to' do
      result = message_sender.send_audio(chat_id, caption, audio: audio_path)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:reply_to]).to be_nil
        expect(args[:input_message_content]).to be_a(TD::Types::InputMessageContent::Audio)
      end
    end

    it 'sends audio with custom parameters' do
      result = message_sender.send_audio(chat_id, caption, audio: audio_path, duration: 180, title: 'My Song', performer: 'Artist Name')
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        content = args[:input_message_content]
        expect(content).to be_a(TD::Types::InputMessageContent::Audio)
        expect(content.duration).to eq(180)
        expect(content.title).to eq('My Song')
        expect(content.performer).to eq('Artist Name')
      end
    end

    it 'sends audio with thumbnail' do
      thumb_path = '/path/to/thumb.jpg'
      
      result = message_sender.send_audio(chat_id, caption, audio: audio_path, thumb: thumb_path)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        content = args[:input_message_content]
        expect(content).to be_a(TD::Types::InputMessageContent::Audio)
        expect(content.album_cover_thumbnail).to be_a(TD::Types::InputThumbnail)
        expect(content.album_cover_thumbnail.thumbnail).to be_a(TD::Types::InputFile::Local)
        expect(content.album_cover_thumbnail.thumbnail.path).to eq(thumb_path)
      end
    end

    it 'sends audio without thumbnail when not provided' do
      result = message_sender.send_audio(chat_id, caption, audio: audio_path)
      
      expect(result).to eq({message_id: 0, text: "Audio caption"})
      expect(mock_client).to have_received(:send_message) do |args|
        content = args[:input_message_content]
        expect(content).to be_a(TD::Types::InputMessageContent::Audio)
        expect(content.album_cover_thumbnail).to be_nil
      end
    end
  end

  describe '#extract_local_path' do
    it 'returns string input as-is' do
      path = '/path/to/file.txt'
      result = message_sender.extract_local_path(path)
      expect(result).to eq(path)
    end

    it 'extracts local_path from hash' do
      hash = { local_path: '/path/from/hash.txt' }
      result = message_sender.extract_local_path(hash)
      expect(result).to eq('/path/from/hash.txt')
    end

    it 'extracts local_path from object with method' do
      obj = double('file_object', local_path: '/path/from/object.txt')
      result = message_sender.extract_local_path(obj)
      expect(result).to eq('/path/from/object.txt')
    end

    it 'returns nil for unsupported input' do
      result = message_sender.extract_local_path(123)
      expect(result).to be_nil
    end
  end
end
