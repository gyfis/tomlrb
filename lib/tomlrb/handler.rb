module Tomlrb
  class Handler
    attr_reader :output, :symbolize_keys

    def initialize(**options)
      @output = {}
      @current = @output
      @stack = []
      @array_names = []
      @current_table = []
      @keys = Keys.new
      @symbolize_keys = options[:symbolize_keys]
    end

    def set_context(identifiers, is_array_of_tables: false)
      @current_table = identifiers
      @keys.add_table_key identifiers, is_array_of_tables
      @current = @output

      deal_with_array_of_tables(identifiers, is_array_of_tables) do |identifierz|
        identifierz.each do |k|
          k = k.to_sym if @symbolize_keys
          if @current[k].is_a?(Array)
            @current[k] << {} if @current[k].empty?
            @current = @current[k].last
          else
            @current[k] ||= {}
            @current = @current[k]
          end
        end
      end
    end

    def deal_with_array_of_tables(identifiers, is_array_of_tables)
      identifiers.map!{|n| n.gsub("\"", '')}
      stringified_identifier = identifiers.join('.')

      if is_array_of_tables
        @array_names << stringified_identifier
        last_identifier = identifiers.pop
      elsif @array_names.include?(stringified_identifier)
        raise ParseError, 'Cannot define a normal table with the same name as an already established array'
      end

      yield(identifiers)

      if is_array_of_tables
        last_identifier = last_identifier.to_sym if @symbolize_keys
        @current[last_identifier] ||= []
        raise ParseError, "Cannot use key #{last_identifier} for both table and array at once" unless @current[last_identifier].respond_to?(:<<)
        @current[last_identifier] << {}
        @current = @current[last_identifier].last
      end
    end

    def assign(k)
      @keys.add_pair_key k, @current_table
      current = @current
      while key = k.shift
        key = k.to_sym if @symbolize_keys
        if k.empty?
          raise ParseError, "Cannot overwrite value with key #{key}" unless current.kind_of?(Hash)
          current[key] = @stack.pop
        else
          current[key] ||= {}
          current = current[key]
        end
      end
    end

    def push(o)
      @stack << o
    end

    def start_(type)
      push([type])
    end

    def end_(type)
      array = []
      while (value = @stack.pop) != [type]
        raise ParseError, 'Unclosed table' if value.nil?
        array.unshift(value)
      end
      array
    end
  end

  class Keys
    def initialize
      @keys = {}
    end

    def add_table_key(keys, is_array_of_tables = false)
      self << [keys, [], is_array_of_tables]
    end

    def add_pair_key(keys, context)
      self << [context, keys, false]
    end

    def <<(keys)
      table_keys, pair_keys, is_array_of_tables = keys
      current = @keys
      table_keys.each_with_index do |key, index|
        declared = (index == table_keys.length - 1) && pair_keys.empty?
        if index == 0
          existed = current[key]
          if existed && existed.type == :pair
            raise Key::KeyConflict, "Key #{key} is already used as #{existed.type} key"
          end
          if existed && existed.declared? && declared && ! is_array_of_tables
            raise Key::KeyConflict, "Key #{key} is already used"
          end
          k = existed || Key.new(key, :table, declared)
          current[key] = k
          current = k
        else
          current = current << [key, :table, declared, is_array_of_tables]
        end
      end
      pair_keys.each_with_index do |key, index|
        declared = index == pair_keys.length - 1
        if index == 0 && table_keys.empty?
          k = Key.new(key, :pair, declared)
          current[key] = k
          current = k
        else
          key = current << [key, :pair, declared, is_array_of_tables]
          current = key
        end
      end
    end
  end

  class Key
    class KeyConflict < ParseError; end

    attr_reader :key, :type

    def initialize(key, type, declared = false)
      @key = key
      @type = type
      @declared = declared
      @children = {}
    end

    def declared?
      @declared
    end

    def <<(key_type_declared)
      key, type, declared, is_array_of_tables = key_type_declared
      existed = @children[key]
      if declared && existed && existed.declared? && existed.type != type
        raise KeyConflict, "Key #{key} is already used as #{existed.type} key"
      end
      if declared && type == :table && existed && existed.declared? && ! is_array_of_tables
        raise KeyConflict, "Key #{key} is already used"
      end
      if declared && (type == :table) && existed && (existed.type == :pair) && (! existed.declared?)
        raise KeyConflict, "Key #{key} is already used as #{existed.type} key"
      end
      if ! declared && (type == :pair) && existed && (existed.type == :pair) && existed.declared?
        raise KeyConflict, "Key #{key} is already used as #{type} key"
      end
      @children[key] = existed || self.class.new(key, type, declared)
    end
  end
end
