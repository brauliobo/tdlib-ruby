require 'spec_helper'

RSpec.describe 'TDLib Refactor Functionality' do
  describe 'Parameter Compatibility' do
    let(:client) { double('client', on: nil, send_message: double(value: double(id: 123))) }
    let(:file_manager) { double('file_manager') }
    let(:sender) { TD::MessageSender.new(client) }
    
    before do
      allow(TD::FileManager).to receive(:new).and_return(file_manager)
      allow(file_manager).to receive(:extract_local_path).and_return('/test/video.mp4')
      allow(file_manager).to receive(:copy_to_safe_location).and_return('/safe/video.mp4')
      allow(file_manager).to receive(:create_dummy_thumbnail).and_return(nil)
      allow(sender).to receive(:parse_markdown_text).and_return(double('formatted_text'))
    end
    
    it 'handles Bot API parameters in send_video without errors' do
      # This is the key test - ensuring the refactored code can handle
      # the parameters that the Bot worker passes
      expect {
        sender.send_video(
          123, 'caption',
          video: double('video'),
          duration: 120,
          width: 640, 
          height: 480,
          # These Bot API parameters should be ignored gracefully:
          star_count: 5,
          thumb: 'thumb_data',
          title: 'Video Title',
          performer: 'Artist Name'
        )
      }.not_to raise_error
    end
    
    it 'handles Bot API parameters in send_document without errors' do
      allow(file_manager).to receive(:extract_local_path).and_return('/test/doc.pdf')
      allow(file_manager).to receive(:copy_to_safe_location).and_return('/safe/doc.pdf')
      
      expect {
        sender.send_document(
          123, 'caption',
          document: double('document'),
          # These Bot API parameters should be ignored gracefully:
          star_count: 10,
          title: 'Document Title'
        )
      }.not_to raise_error
    end
  end
  
  describe 'Message Structure Compatibility' do
    let(:client) { double('client', get_self_id: 123456) }
    let(:handler) { TD::MessageHandler.new(client) }
    
    it 'creates SymMash objects compatible with Bot class expectations' do
      orig_msg = double('orig_msg',
        to_h: { id: 789, date: 1234567890 },
        chat_id: 456,
        sender_id: double('sender', respond_to?: true, user_id: 999),
        id: 789,
        content: double('content')
      )
      
      allow(handler).to receive(:extract_message_text).and_return('test message')
      
      result = handler.create_message_object(orig_msg)
      
      # Test that the result has the structure expected by Bot class
      expect(result).to respond_to(:from)
      expect(result).to respond_to(:chat_id)
      expect(result).to respond_to(:id)
      expect(result).to respond_to(:text)
      
      # Test that nested access works (Bot class uses msg.from.id)
      expect(result.from).to respond_to(:[])
      expect(result.from[:id]).to eq(999)
      expect(result.chat_id).to eq(456)
    end
  end
  
  describe 'Logging Integration' do
    let(:test_class) do
      Class.new do
        include TD::Logging
      end
    end
    
    it 'provides dlog method for debug output' do
      instance = test_class.new
      
      # Should not raise errors when called
      expect { instance.dlog('test message') }.not_to raise_error
      expect { test_class.dlog('class message') }.not_to raise_error
    end
  end
  
  describe 'File Management' do
    let(:client) { double('client') }
    let(:file_manager) { TD::FileManager.new(client) }
    
    it 'handles basic file operations' do
      # Test basic functionality without complex mocking
      expect(file_manager.extract_local_path('/test/path.mp4')).to eq('/test/path.mp4')
      expect(file_manager.extract_local_path(nil)).to be_nil
      
      # Test error handling
      result = file_manager.download_file(nil)
      expect(result[:error]).to eq('no file_id')
    end
  end
end
