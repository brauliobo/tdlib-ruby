require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe TD::FileManager do
  let(:mock_client) { double('TD::Client') }
  let(:file_manager) { TD::FileManager.new(mock_client) }
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_file_path) { File.join(temp_dir, 'test_file.txt') }

  before do
    # Create a test file
    File.write(test_file_path, 'test content')
    
    # Mock the logging method
    allow(file_manager).to receive(:dlog)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#download_file' do
    let(:mock_file_info) do
      double('file_info',
        local: double('local', 
          is_downloading_completed: true,
          path: test_file_path
        ),
        remote: double('remote', id: 'remote123'),
        size: 12
      )
    end

    let(:mock_get_file_result) { double('get_file_result', value: mock_file_info) }

    before do
      allow(mock_client).to receive(:get_file).and_return(mock_get_file_result)
    end

    context 'with simple file_id' do
      it 'downloads file successfully' do
        result = file_manager.download_file(123)
        
        expect(result).to eq({
          local_path: test_file_path,
          remote_id: 'remote123',
          size: 12
        })
        expect(mock_client).to have_received(:get_file).with(file_id: 123)
      end
    end

    context 'with document object' do
      let(:document_obj) { double('document', document: double('doc', file_id: 456)) }
      
      it 'extracts file_id from document object' do
        result = file_manager.download_file(document_obj)
        
        expect(result[:local_path]).to eq(test_file_path)
        expect(mock_client).to have_received(:get_file).with(file_id: 456)
      end
    end

    context 'with document having id instead of file_id' do
      let(:document_obj) { double('document', document: double('doc', id: 789)) }
      
      before do
        allow(document_obj.document).to receive(:respond_to?).with(:file_id).and_return(false)
        allow(document_obj.document).to receive(:respond_to?).with(:id).and_return(true)
      end
      
      it 'extracts id from document object' do
        result = file_manager.download_file(document_obj)
        
        expect(result[:local_path]).to eq(test_file_path)
        expect(mock_client).to have_received(:get_file).with(file_id: 789)
      end
    end

    context 'with dir parameter' do
      let(:target_dir) { File.join(temp_dir, 'target') }
      
      it 'copies file to specified directory' do
        result = file_manager.download_file(123, dir: target_dir)
        
        expect(result[:local_path]).to eq(File.join(target_dir, 'test_file.txt'))
        expect(File.exist?(result[:local_path])).to be true
        expect(File.read(result[:local_path])).to eq('test content')
      end
    end

    context 'when file needs downloading' do
      let(:mock_file_info_incomplete) do
        double('file_info',
          local: double('local', is_downloading_completed: false),
          remote: double('remote', id: 'remote123'),
          size: 12
        )
      end

      let(:mock_download_result) do
        double('download_result',
          local: double('local', path: test_file_path),
          remote: double('remote', id: 'remote123'),
          size: 12
        )
      end

      before do
        allow(mock_get_file_result).to receive(:value).and_return(mock_file_info_incomplete)
        allow(mock_client).to receive(:download_file).and_return(double(value: mock_download_result))
      end

      it 'downloads file when not completed' do
        result = file_manager.download_file(123)
        
        expect(result[:local_path]).to eq(test_file_path)
        expect(mock_client).to have_received(:download_file).with(
          file_id: 123,
          priority: 32,
          offset: 0,
          limit: 0,
          synchronous: true
        )
      end
    end

    context 'error handling' do
      it 'returns error when no file_id provided' do
        result = file_manager.download_file(nil)
        expect(result[:error]).to eq('no file_id')
      end

      it 'returns error when get_file fails' do
        allow(mock_get_file_result).to receive(:value).and_return(nil)
        
        result = file_manager.download_file(123)
        expect(result[:error]).to eq('file info failed')
      end

      it 'handles exceptions gracefully' do
        allow(mock_client).to receive(:get_file).and_raise(StandardError, 'test error')
        
        result = file_manager.download_file(123)
        expect(result[:error]).to eq('StandardError: test error')
      end
    end
  end

  describe 'private methods' do
    describe '#extract_file_id' do
      it 'extracts from various object types' do
        # Test document with file_id
        doc_with_file_id = double('msg', document: double('doc', file_id: 123))
        expect(file_manager.send(:extract_file_id, doc_with_file_id)).to eq(123)
        
        # Test object with direct file_id
        obj_with_file_id = double('obj', file_id: 456)
        expect(file_manager.send(:extract_file_id, obj_with_file_id)).to eq(456)
        
        # Test document with id
        doc_with_id = double('msg', document: double('doc', id: 789))
        allow(doc_with_id.document).to receive(:respond_to?).with(:file_id).and_return(false)
        allow(doc_with_id.document).to receive(:respond_to?).with(:id).and_return(true)
        expect(file_manager.send(:extract_file_id, doc_with_id)).to eq(789)
        
        # Test object with id
        obj_with_id = double('obj', id: 101112)
        allow(obj_with_id).to receive(:respond_to?).with(:document).and_return(false)
        allow(obj_with_id).to receive(:respond_to?).with(:file_id).and_return(false)
        allow(obj_with_id).to receive(:respond_to?).with(:id).and_return(true)
        expect(file_manager.send(:extract_file_id, obj_with_id)).to eq(101112)
        
        # Test plain integer
        expect(file_manager.send(:extract_file_id, 999)).to eq(999)
      end
    end

    describe '#copy_to_directory' do
      let(:target_dir) { File.join(temp_dir, 'target') }
      
      it 'copies file to target directory' do
        result = file_manager.send(:copy_to_directory, test_file_path, target_dir)
        
        expect(result).to eq(File.join(target_dir, 'test_file.txt'))
        expect(File.exist?(result)).to be true
        expect(File.read(result)).to eq('test content')
      end

      it 'creates target directory if it does not exist' do
        expect(Dir.exist?(target_dir)).to be false
        
        file_manager.send(:copy_to_directory, test_file_path, target_dir)
        
        expect(Dir.exist?(target_dir)).to be true
      end

      it 'returns nil when source file does not exist' do
        non_existent = File.join(temp_dir, 'non_existent.txt')
        result = file_manager.send(:copy_to_directory, non_existent, target_dir)
        
        expect(result).to be_nil
      end

      it 'handles copy errors gracefully' do
        allow(FileUtils).to receive(:cp).and_raise(StandardError, 'copy failed')
        
        result = file_manager.send(:copy_to_directory, test_file_path, target_dir)
        
        expect(result).to be_nil
      end
    end
  end
end
