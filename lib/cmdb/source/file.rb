# encoding: utf-8
require 'uri'

module CMDB
  # Data source that is backed by a YAML/JSON file that lives in the filesystem. The name of the
  # file becomes the top-level key under which all values in the file are exposed, preserving
  # their exact structure as parsed by YAML/JSON.
  #
  # @example Use my.yml as a CMDB source
  #    source = Source::File.new('/tmp/my.yml') # contains a top-level stanza named "database"
  #    source['my']['database']['host'] # => 'db1-1.example.com'
  class Source::File < Source
    # Read a data file whose location is specified by a file:// URI.
    #
    # @param [URI] uri logical description of this source
    # @param [String] prefix unique dot-notation prefix of all this source's keys, if any
    # @raise [BadData] if the file's content is malformed
    def initialize(uri, prefix)
      super(uri, prefix)
      path = @uri.path
      filename  = ::File.basename(path)
      extension = ::File.extname(filename)
      raw_bytes = ::File.read(path)
      raw_data  = nil

      begin
        case extension
        when /jso?n?$/i
          raw_data = JSON.load(raw_bytes)
        when /ya?ml$/i
          raw_data = YAML.load(raw_bytes)
        else
          raise BadData.new(@uri, 'file with unknown extension; expected js(on) or y(a)ml')
        end
      rescue StandardError
        raise BadData.new(@uri, 'CMDB data file')
      end

      @data = {}
      flatten(raw_data, @prefix, @data)
    end

    # Get the value of key.
    #
    # @return [Object] the key's value, or nil if not found
    def get(key)
      @data[key]
    end

    # Enumerate the keys and values in this source.
    #
    # @yield every key/value in the source
    # @yieldparam [String] key
    # @yieldparam [Object] value
    def each_pair(&_block)
      @data.each_pair { |k, v| yield(k, v) }
    end

    private

    def flatten(data, prefix, output)
      data.each_pair do |key, value|
        key = CMDB.join(prefix, key)
        case value
        when Hash
          flatten(value, key, output)
        when Array
          if value.any? { |e| e.is_a?(Hash) }
            # mismatched arrays: not allowed
            raise BadValue.new(uri, key, value, 'hashes not allowed inside arrays')
          elsif value.all? { |e| e.is_a?(String) } ||
             value.all? { |e| e.is_a?(Numeric) } ||
             value.all? { |e| e == true } ||
             value.all? { |e| e == false }
            output[key] = value
          else
            # mismatched arrays: not allowed
            raise BadValue.new(uri, key, value, 'mismatched/unsupported element types')
          end
        when String, Numeric, TrueClass, FalseClass
          output[key] = value
        else
          # nil and anything else: not allowed
          raise BadValue.new(uri, key, value)
        end
      end
    end
  end
end
