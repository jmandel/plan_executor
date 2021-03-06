module Crucible
  module Tests
    class BaseSuite < BaseTest

      def title
        self.class.name.demodulize
      end

      def parse_operation_outcome(body)
        # body should be a String
        outcome = nil
        if 0==(body =~ /^[<?xml]/)
          outcome = FHIR::OperationOutcome.from_xml(body)
        else # treat as JSON
          outcome = FHIR::OperationOutcome.from_fhir_json(body)
        end
        outcome
      end

      def build_messages(operation_outcome)
        messages = []
        if !operation_outcome.nil? and !operation_outcome.issue.nil?
          operation_outcome.issue.each {|issue| messages << "#{issue.severity} : #{issue.details}" }
        end
        messages
      end

      def fhir_resources
        Mongoid.models.select {|c| c.name.include?('FHIR') && !c.included_modules.find_index(FHIR::Resource).nil?}
      end

      def requires(hash)
        @requires << hash
      end

      def validates(hash)
        @validates << hash
      end

      def links(url)
        @links << url
      end

      def collect_metadata(methods_only=false)
        @metadata_only = true
        if @resource_class
          result = execute(@resource_class)
        else
          result = execute
        end
        result = result.map{|r| r.values.first[:tests]}.flatten if methods_only
        @metadata_only = false
        result
      end

      def metadata(&block)
        yield
        skip if @setup_failed
        skip if @metadata_only
      end

      def tests_by_conformance(conformance_resources=nil, metadata=nil)
        return tests unless conformance_resources
        # array of metadata from current suite's test methods
        suite_metadata = metadata || collect_metadata(true)
        # { fhirType => supported codes }
        methods = []
        # include tests with undefined metadata
        methods.push suite_metadata.select{|sm| sm["requires"].blank?}.map {|sm| sm[:test_method]}
        # parse tests with defined metadata
        suite_metadata.select{|sm| !sm["requires"].blank?}.each do |test|
          unsupported = []
          # determine if any of the metadata requirements match the conformance information
          test["requires"].each do |req|
            diffs = (req[:methods] - ( conformance_resources[req[:resource]] || [] ))
            unsupported.push({req[:resource].to_sym => diffs}) unless diffs.blank?
          end
          # print debug if unsupported, otherwise add to supported methods
          if !unsupported.blank?
            puts "UNSUPPORTED #{test[:test_method]}: #{unsupported}"
          else
            methods.push test[:test_method]
          end
        end
        methods.flatten
      end

      def self.test(key, desc, &block)
        test_method = "#{key} #{desc} test".downcase.tr(' ', '_').to_sym
        contents = block
        wrapped = -> () do
          @warnings, @links, @requires, @validates = [],[],[],[]
          description = nil
          if respond_to? :supplement_test_description
            description = supplement_test_description(desc)
          else
            description = desc
          end
          result = TestResult.new(key, description, STATUS[:pass], '','')
          begin
            t = instance_eval &block
            result.update(t.status, t.message, t.data) if !t.nil? && t.is_a?(Crucible::Tests::TestResult)
          rescue AssertionException => e
            result.update(STATUS[:fail], e.message, e.data)
          rescue SkipException => e
            result.update(STATUS[:skip], "Skipped: #{test_method}", '')
          rescue => e
            result.update(STATUS[:error], "Fatal Error: #{e.message}", e.backtrace.join("\n"))
          end
          result.update(STATUS[:skip], "Skipped because setup failed.", "-") if @setup_failed
          result.warnings = @warnings unless @warnings.empty?
          result.requires = @requires unless @requires.empty?
          result.validates = @validates unless @validates.empty?
          result.links = @links unless @links.empty?
          result.id = key
          result.code = contents.source
          result.id = "#{result.id}_#{result_id_suffix}" if respond_to? :result_id_suffix # add the resource to resource based tests to make ids unique

          result
        end
        define_method test_method, wrapped
      end

    end
  end
end
