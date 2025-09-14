require 'spec_helper'

RSpec.describe 'TDLib Extensions Integration' do
  describe 'TD::Logging' do
    let(:test_class) do
      Class.new do
        include TD::Logging
      end
    end
    
    it 'includes logging functionality' do
      expect(test_class.new).to respond_to(:dlog)
      expect(test_class).to respond_to(:dlog)
    end
  end
  
  describe 'TD::FileManager' do
    let(:client) { double('client') }
    let(:file_manager) { TD::FileManager.new(client) }
    
    it 'initializes with client' do
      expect(file_manager.client).to eq(client)
    end
    
    it 'handles string paths' do
      expect(file_manager.extract_local_path('/test/path.mp4')).to eq('/test/path.mp4')
    end
    
    it 'handles nil input' do
      expect(file_manager.extract_local_path(nil)).to be_nil
    end
    
    it 'returns error for missing file_id' do
      result = file_manager.download_file(nil)
      expect(result[:error]).to eq('no file_id')
    end
    
    it 'creates dummy thumbnail' do
      expect(file_manager.create_dummy_thumbnail).to be_a(TD::Types::InputThumbnail)
    end
  end
  
  describe 'TD::MessageHandler' do
    let(:client) { double('client', get_self_id: 123) }
    let(:handler) { TD::MessageHandler.new(client) }
    
    it 'initializes with client' do
      expect(handler.client).to eq(client)
      expect(handler.known_chat_ids).to be_empty
      expect(handler.message_id_map).to be_empty
    end
    
    it 'rejects nil messages' do
      expect(handler.should_process_message?(nil)).to be false
    end
    
    it 'extracts text from unknown message types' do
      message = double('message', content: double('content'))
      expect(handler.extract_message_text(message)).to be_nil
    end
  end
  
  describe 'TD::MessageSender' do
    let(:client) { double('client', on: nil) }
    let(:file_manager) { double('file_manager') }
    
    before do
      allow(TD::FileManager).to receive(:new).and_return(file_manager)
    end
    
    it 'initializes with client and file manager' do
      sender = TD::MessageSender.new(client)
      expect(sender.client).to eq(client)
      expect(sender.file_manager).to eq(file_manager)
    end
  end
  
  describe 'Integration with media-downloader-bot' do
    it 'loads all required modules' do
      expect(defined?(TD::Logging)).to be_truthy
      expect(defined?(TD::FileManager)).to be_truthy
      expect(defined?(TD::MessageHandler)).to be_truthy
      expect(defined?(TD::MessageSender)).to be_truthy
    end
    
    it 'provides high-level interfaces' do
      # These are the key interfaces used by the refactored helpers.rb
      client = double('client', on: nil)
      
      # Test that we can create instances without errors
      expect { TD::MessageHandler.new(client) }.not_to raise_error
      expect { TD::MessageSender.new(client) }.not_to raise_error
      expect { TD::FileManager.new(client) }.not_to raise_error
    end
  end
end
