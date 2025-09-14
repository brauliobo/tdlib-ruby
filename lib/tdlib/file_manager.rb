require_relative 'logging'
require 'fileutils'

module TD
  class FileManager
    include TD::Logging
    
    attr_reader :client
    
    def initialize(client)
      @client = client
    end
    
    def download_file(file_id, priority: 32, offset: 0, limit: 0, synchronous: true)
      return {error: 'no file_id'} unless file_id
      
      begin
        file_info = client.get_file(file_id: file_id).value(30)
        return {error: 'file info failed'} unless file_info
        
        if file_info.local.is_downloading_completed
          return {
            local_path: file_info.local.path,
            remote_id: file_info.remote.id,
            size: file_info.size
          }
        end
        
        download_result = client.download_file(
          file_id: file_id,
          priority: priority,
          offset: offset,
          limit: limit,
          synchronous: synchronous
        ).value(120)
        
        return {error: 'download failed'} unless download_result
        
        {
          local_path: download_result.local.path,
          remote_id: download_result.remote.id,
          size: download_result.size
        }
      rescue => e
        {error: "#{e.class}: #{e.message}"}
      end
    end
    
    def copy_to_safe_location(original_path)
      return original_path unless File.exist?(original_path)
      
      # Create safe upload directory
      safe_dir = File.join(Dir.tmpdir, 'tdbot-uploads')
      FileUtils.mkdir_p(safe_dir)
      
      # Generate unique filename
      basename = File.basename(original_path)
      timestamp = Time.now.to_f.to_s.tr('.', '')
      safe_filename = "#{timestamp}_#{basename}"
      safe_path = File.join(safe_dir, safe_filename)
      
      # Copy file
      FileUtils.cp(original_path, safe_path)
      dlog "[SAFE_COPY] #{original_path} -> #{safe_path}"
      
      # Schedule cleanup after 5 minutes
      schedule_cleanup(safe_path)
      
      safe_path
    end
    
    def extract_local_path(obj)
      return obj if obj.is_a?(String)
      return obj.path if obj.respond_to?(:path)
      
      begin
        io = obj.instance_variable_get(:@io)
        return io.path if io && io.respond_to?(:path)
      rescue
        # ignore
      end
      
      nil
    end
    
    def create_dummy_thumbnail
      TD::Types::InputThumbnail.new(
        thumbnail: TD::Types::InputFile::Remote.new(id: '0'),
        width: 0,
        height: 0
      )
    end
    
    private
    
    def schedule_cleanup(safe_path)
      Thread.new do
        sleep 300  # 5 minutes
        File.delete(safe_path) if File.exist?(safe_path)
        dlog "[SAFE_CLEANUP] deleted #{safe_path}"
      rescue => e
        dlog "[SAFE_CLEANUP_ERROR] #{e.class}: #{e.message}"
      end
    end
  end
end
