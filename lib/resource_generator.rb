module Crucible
  module Tests
    class ResourceGenerator

      #
      # Generate a FHIR resource for the given class `klass`
      # If `embedded` is greater than zero, all embedded children will also
      # be generated.
      #
      def self.generate(klass,embedded=0)
        resource = klass.new
        Time.zone = 'UTC'
        set_fields!(resource)
        if(embedded > 0)
          generate_children!(resource,embedded)
        end
        resource.xmlId=nil if resource.respond_to?(:xmlId=)
        resource.versionId=nil if resource.respond_to?(:versionId=)
        resource.version=nil if resource.respond_to?(:version=)
        resource
      end

      #
      # Set the fields of this resource to have some random values.
      #
      def self.set_fields!(resource)
        # Organize some of the validators
        validators = {}
        resource.class.validators.collect{|v| v if v.class==Mongoid::Validatable::FormatValidator}.compact.each do |v|
          v.attributes.each{|a| validators[a] = v.options[:with]}
        end

        # For now, we'll skip fields that can have multiple datatypes, such as attribute[x]
        multiples = []
        if resource.class.constants.include? :MULTIPLE_TYPES
          multiples = resource.class::MULTIPLE_TYPES.map{|k,v| v}.flatten
        end

        # Get valid codes
        valid_codes = {}
        if resource.class.constants.include? :VALID_CODES
          valid_codes = resource.class::VALID_CODES
        end

        fields = resource.fields
        fields.each do |key,value|
          type = value.options[:type]
		      next if key=='id' || key=='xmlId'
          next if multiples.include? key
          gen = nil
          if type == String
            gen = SecureRandom.urlsafe_base64
            if valid_codes[key.to_sym]
              valid_values = valid_codes[key.to_sym]
              if !valid_values.nil?
                gen = valid_values[ SecureRandom.random_number( valid_values.length ) ]
              end
            elsif validators[key.to_sym]
              date = DateTime.now
              regex = validators[key.to_sym]
              if date.strftime("%Y-%m-%dT%T.%LZ%z").match(regex)
                gen = date.strftime("%Y-%m-%dT%T.%LZ%z")
              elsif date.strftime("%Y-%m-%d").match(regex)
                gen = date.strftime("%Y-%m-%d")
              elsif date.strftime("%T").match(regex)
                gen = date.strftime("%T")
              end
            end
          elsif type == Integer
            gen = SecureRandom.random_number(100)
          elsif type == Float
            gen = SecureRandom.random_number
            while gen.to_s.match(/e/) # according to FHIR spec: decimals may not contain exponents
              gen = SecureRandom.random_number
            end
          elsif type == Mongoid::Boolean
            gen = (SecureRandom.random_number(100) % 2 == 0)
          elsif type == BSON::Binary
            # gen = SecureRandom.random_bytes
            gen = SecureRandom.base64
          elsif type == BSON::ObjectId or type == Array or type == Object or type == FHIR::AnyType
            gen = nil # ignore
          # else
          #   puts "Unable to generate field #{key} for #{resource.class} -- unrecognized type: #{type}"
          end
          # TODO: Improve field value generation for coded fields
          gen = gen[0..19] if key == 'language'
          resource[key] = gen if !gen.nil?
        end
        resource
      end


      #
      # Generate children for this resource.
      #
      def self.generate_children!(resource,embedded=0)
        # For now, we'll skip fields that can have multiple datatypes, such as attribute[x]
        multiples = []
        if resource.class.constants.include? :MULTIPLE_TYPES
          multiples = resource.class::MULTIPLE_TYPES.map{|k,v| v}.flatten
        end

        children = resource.embedded_relations
        children.each do |key,value|
          # TODO: Determine if we can generate references or meta information
          next if ['meta'].include? key
          next if multiples.include? key
          # TODO: Ignore references if we don't explicitly require them
          next if value[:class_name] == 'FHIR::Reference'
          klass = resource.get_fhir_class_from_resource_type(value[:class_name])
          child = generate(klass,(embedded-1)) if(value[:class_name] != 'FHIR::Extension')
          if value[:relation] == Mongoid::Relations::Embedded::Many
            child = ([] << child) if child
          end
          resource[key] = child if child
        end
        resource
      end

    end
  end
end
