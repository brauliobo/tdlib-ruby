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
        
        expect(result).to eq(mock_result)
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
        
        expect(result).to eq(mock_result)
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
      
      expect(result).to eq(mock_result)
      expect(mock_client).to have_received(:edit_message_text) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:message_id]).to eq(message_id)
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
      result = message_sender.delete_message(chat_id, message_id)
      
      expect(result).to eq(mock_result)
      expect(mock_client).to have_received(:delete_messages) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:message_ids]).to eq([message_id])
        expect(args[:revoke]).to be true
      end
    end

    it 'handles delete failures gracefully' do
      allow(mock_delete_result).to receive(:value).and_return(nil)
      
      result = message_sender.delete_message(chat_id, message_id)
      
      expect(result).to be_nil
    end

    it 'handles exceptions gracefully' do
      allow(mock_client).to receive(:delete_messages).and_raise(StandardError, 'delete failed')
      
      result = message_sender.delete_message(chat_id, message_id)
      
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
      
      expect(result).to eq(mock_result)
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
        expect(args[:reply_to].message_id).to eq(reply_message_id)
      end
    end

    it 'sends video without reply_to' do
      result = message_sender.send_video(chat_id, caption, video: video_path)
      
      expect(result).to eq(mock_result)
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
      
      expect(result).to eq(mock_result)
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:chat_id]).to eq(chat_id)
        expect(args[:reply_to]).to be_a(TD::Types::InputMessageReplyTo::Message)
        expect(args[:reply_to].message_id).to eq(reply_message_id)
      end
    end

    it 'sends document without reply_to' do
      result = message_sender.send_document(chat_id, caption, document: document_path)
      
      expect(result).to eq(mock_result)
      expect(mock_client).to have_received(:send_message) do |args|
        expect(args[:reply_to]).to be_nil
      end
    end
  end
end
