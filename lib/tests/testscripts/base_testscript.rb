module Crucible
  module Tests
    class BaseTestScript < BaseTest

      ASSERTION_MAP = {
        # equals	expected (value1 or xpath expression2) actual (value1 or xpath expression2)	Asserts that "expected" is equal to "actual".
        "equals" => :assert_equal,
        # fixture_equals expected_fixture_id, expected_xpath, actual_fixture_id, actual_xpath Asserts that "expected_xpath" in "expected_fixture_id" is equal to "actual_xpath" in "actual_fixture_id"
        "fixture_equals" => :assert_equal,
        # fixture_compare fixture_id, fixture_xpath, actual (value or xpath expression) Asserts that "fixture_xpath" in "fixture_id" is equal to "actual"
        "fixture_compare" => :assert_equal,
        # response_code	code (numeric HTTP response code)	Asserts that the response code equals "code".
        "response_code" => :assert_response_code,
        # response_okay	N/A	Asserts that the response code is in the set (200, 201).
        "response_okay" => :assert_response_ok,
        # response_created N/A Asserts that the response code is 201.
        "response_created" => :assert_response_created,
        # response_gone N/A Asserts that the response code is 410.
        "response_gone" => :assert_response_gone,
        # response_not_found	N/A	Asserts that the response code is 404.
        "response_not_found" => :assert_response_not_found,
        # response_bad	N/A	Asserts that the response code is 400.
        "response_bad" => :assert_response_bad,
        # navigation_links	Bundle	Asserts that the Bundle contains first, last, and next links.
        "navigation_links" => :assert_nagivation_links,
        # resource_type	resourceType (string)	Asserts that the response contained a FHIR Resource of the given "resourceType".
        "resource_type" => :assert_resource_type,
        # valid_content_type	N/A	Asserts that the response contains a "content-type" is either "application/xml+fhir" or "application/json+fhir" and that "charset" is specified as "UTF-8"
        "valid_content_type" => :assert_valid_resource_content_type_present,
        # valid_content_location	N/A	Asserts that the response contains a valid "content-location" header.
        "valid_content_location" => :assert_valid_content_location_present,
        # valid_last_modified N/A Asserts that the response contains a valid "last-modified" header.
        "valid_last_modified" => :assert_last_modified_present,
        # bundle_response N/A Asserts that the response is a bundle.
        "bundle_response" => :assert_bundle_response,
        # bundle_entry_count count (number of entries expected) Asserts that the number of entries matches expectations.
        "bundle_entry_count" => :assert_bundle_entry_count,
        # minimum fixture_id Assert that the last response's resource contains at least the components in "fixture_id"
        "minimum" => :assert_minimum
      }

      def initialize(testscript, client, client2=nil)
        super(client, client2)
        @id_map = {}
        @response_map = {}
        @warnings = []
        @autocreate = []
        @autodelete = []
        @testscript = testscript
        define_tests
        load_fixtures
      end

      def author
        @testscript.name
      end

      def description
        @testscript.description
      end

      def id
        @testscript.xmlId
      end

      def title
        "TS-#{id}"
      end

      def tests
        @testscript.test.map { |test| "#{test.xmlId} #{test.name} test".downcase.tr(' ', '_').to_sym }
      end

      def debug_prefix
        "[TESTSCRIPT]:\t"
      end

      def log(message)
        puts "#{debug_prefix}#{message}"
      end

      def define_tests
        @testscript.test.each do |test|
          test_method = "#{test.xmlId} #{test.name} test".downcase.tr(' ', '_').to_sym
          define_singleton_method test_method, -> { process_test(test) }
        end
      end

      def load_fixtures
        @fixtures = {}
        @testscript.fixture.each do |fixture|
          if !fixture.uri.nil?
            @fixtures[fixture.xmlId] = Generator::Resources.new.load_fixture(fixture.uri)
          else
            @fixtures[fixture.xmlId] = fixture.resource
          end
          @autocreate << fixture.xmlId if fixture.autocreate
          @autodelete << fixture.xmlId if fixture.autodelete
        end
      end

      def collect_metadata(methods_only=false)
        @metadata_only = true
        result = execute
        result = result.map{|r| r.values.first[:tests]}.flatten if methods_only
        @metadata_only = false
        result
      end

      def process_test(test)
        result = TestResult.new(test.xmlId, test.name, STATUS[:pass], '','')
        @last_response = nil # clear out any responses from previous tests
        begin
          test.operation.each do |op|
            @negated = false # clear out any negations from previous tests
            @warned = false # clear out any warnings from previous tests
            execute_operation op
          end unless @setup_failed || @metadata_only
          # result.update(t.status, t.message, t.data) if !t.nil? && t.is_a?(Crucible::Tests::TestResult)
        rescue AssertionException => e
          result.update(STATUS[:fail], e.message, e.data)
        rescue => e
          result.update(STATUS[:error], "Fatal Error: #{e.message}", e.backtrace.join("\n"))
        end
        result.update(STATUS[:skip], "Skipped because setup failed.", "-") if @setup_failed
        if !test.metadata.nil?
          result.requires = test.metadata.requires.map {|r| {resource: r.fhirType, methods: r.operations.try(:split, ', ')} } unless test.metadata.requires.empty?
          result.validates = test.metadata.validates.map {|r| {resource: r.fhirType, methods: r.operations.try(:split, ', ')} } unless test.metadata.requires.empty?
          result.links = test.metadata.link.map(&:url) if !test.metadata.link.empty?
          result.warnings = @warnings unless @warnings.empty?
        end
        result
      end

      def setup
        return if @testscript.setup.blank? && @autocreate.empty?
        @setup_failed = false
        begin
          @autocreate.each do |fixture_id|
            @last_response = @client.create @fixtures[fixture_id]
            @id_map[fixture_id] = @last_response.id
          end unless @client.nil?
          @testscript.setup.operation.each do |op|
            execute_operation op
          end unless @testscript.setup.blank?
        rescue AssertionException
          @setup_failed = true
        end
      end

      def teardown
        return if @testscript.teardown.blank? && @autodelete.empty?
        @testscript.teardown.operation.each do |op|
          # Assertions in teardown have no effect
          next if op.fhirType.start_with?('assertion')
          execute_operation op
        end unless @testscript.teardown.blank?
        @autodelete.each do |fixture_id|
          @last_response = @client.destroy @fixtures[fixture_id].class, @id_map[fixture_id]
          @id_map.delete(fixture_id)
        end unless @client.nil?
      end

      def execute_operation(operation)
        return if @client.nil?
        case operation.fhirType
        when 'create'
          @last_response = @client.create @fixtures[operation.source]
          @id_map[operation.source] = @last_response.id
        when 'update'
          target_id = @id_map[operation.target]
          fixture = @fixtures[operation.source]
          @last_response = @client.update fixture, target_id
        when 'read'
          if !operation.target.nil?
            @last_response = @client.read @fixtures[operation.target].class, @id_map[operation.target]
          else
            resource_type = operation.parameter.try(:first)
            resource_id = operation.parameter.try(:second)
            @last_response = @client.read "FHIR::#{resource_type}", resource_id
          end
        when 'delete'
          @last_response = @client.destroy @fixtures[operation.target].class, @id_map[operation.target]
          @id_map.delete(operation.target)
        when 'history'
          target_id = @id_map[operation.target]
          fixture = @fixtures[operation.target]
          @last_response = @client.resource_instance_history(fixture.class,target_id)
        when '$expand'
          @last_response = @client.value_set_expansion( extract_operation_parameters(operation) )
        when '$validate'
          @last_response = @client.value_set_code_validation( extract_operation_parameters(operation) )
        when 'assertion'
          handle_assertion(operation)
        when 'assertion_false'
          @negated = true
          handle_assertion(operation)
        when 'assertion_warning'
          @warned = true
          handle_assertion(operation)
        else
          raise "Undefined operation for #{@testscript.name}-#{title}: #{operation.fhirType}"
        end
        handle_response(operation)
      end

      def handle_assertion(operation)
        assertion = operation.parameter.first
        response = @response_map[operation.responseId] || @last_response
        if assertion.start_with? "code"
          code = assertion.split(":").last
          assertion = assertion.split(":").first
        end
        if self.methods.include?(ASSERTION_MAP[assertion])
          method = self.method(ASSERTION_MAP[assertion])
          log "ASSERTING: #{operation.fhirType} - #{assertion}"
          case assertion
          when "code"
            call_assertion(method, response, [code])
          when "resource_type"
            resource_type = "FHIR::#{operation.parameter[1]}".constantize
            call_assertion(method, response, [resource_type])
          when "response_code"
            code = operation.parameter[1]
            call_assertion(method, response, [code.to_i])
          when "equals"
            expected, actual = handle_equals(operation, response, method)
            call_assertion(method, expected, [actual])
          when "fixture_equals"
            expected, actual = handle_fixture_equals(operation, response, method)
            call_assertion(method, expected, [actual])
          when "fixture_compare"
            expected, actual = handle_fixture_compare(operation, response, method)
            call_assertion(method, expected, [actual])
          when "minimum"
            fixture_id = operation.parameter[1]
            fixture = @fixtures[fixture_id] || @response_map[fixture_id].try(:resource)
            call_assertion(method, response, [fixture])
          else
            params = operation.parameter[1..-1]
            call_assertion(method, response, params)
          end
        else
          raise "Undefined assertion for #{@testscript.name}-#{title}: #{operation.parameter}"
        end
      end

      def call_assertion(method, value, params)
        if @warned
          warning { method.call(value, *params) }
        else
          method.call(value, *params)
        end
      end

      def extract_operation_parameters(operation)
        options = {
          :id => @id_map[operation.target]
        }
        operation.parameter.each do |param|
          key, value = param.split("=")
          options[key.to_sym] = value
        end unless operation.parameter.blank?
        options
      end

      def handle_response(operation)
        if !operation.responseId.blank? && !operation.fhirType.start_with?('assertion') && operation.fhirType != 'delete'
          log "Overwriting response #{operation.responseId}..." if @response_map.keys.include?(operation.responseId)
          log "Storing response #{operation.responseId}..."
          @response_map[operation.responseId] = @last_response
        end
      end

      def handle_equals(operation, response, method)
        raise "#{method} expects two parameters: [expected value, actual xpath]" unless operation.parameter.length >= 3
        expected, actual = operation.parameter[1..2]
        resource_xml = response.try(:resource).try(:to_xml) || response.body

        if is_xpath(expected)
          expected = extract_xpath_value(method, resource_xml, expected)
        end
        if is_xpath(actual)
          actual = extract_xpath_value(method, resource_xml, actual)
        end

        return expected, actual
      end

      def handle_fixture_equals(operation, response, method)
        # fixture_equals(fixture-id, fixture-xpath, actual)

        fixture_id, fixture_xpath, actual = operation.parameter[1..3]
        raise "#{method} expects a fixture_id as the second operation parameter" unless !fixture_id.blank?
        raise "#{fixture_id} does not exist" unless ( @fixtures.keys.include?(fixture_id) || @response_map.keys.include?(fixture_id) )
        raise "#{method} expects a fixture_xpath as the third operation parameter" unless !fixture_xpath.blank?
        raise "#{method} expects an actual value as the fourth operation parameter" unless !actual.blank?
        raise "#{method} expects fixture_xpath to be a valid xpath" unless is_xpath(fixture_xpath)

        fixture = @fixtures[fixture_id] || @response_map[fixture_id].try(:resource)
        expected = extract_xpath_value(method, fixture.try(:to_xml), fixture_xpath)

        if is_xpath(actual)
          response_xml = response.resource.try(:to_xml) || response.body
          actual = extract_xpath_value(method, response_xml, actual)
        end

        return expected, actual
      end

      def handle_fixture_compare(operation, response, method)
        # fixture_compare(expected_fixture_id, expected_xpath, actual_fixture, actual_xpath)

        expected_fixture_id, expected_xpath, actual_fixture_id, actual_xpath = operation.parameter[1..4]
        raise "#{method} expects expected_fixture_id as the operation parameter" unless !expected_fixture_id.blank?
        raise "#{expected_fixture_id} does not exist" unless ( @fixtures.keys.include?(expected_fixture_id) || @response_map.keys.include?(expected_fixture_id) )
        raise "#{method} expects expected_xpath as the operation parameter" unless !expected_xpath.blank?
        raise "#{method} expects actual_fixture_id as the operation parameter" unless !actual_fixture_id.blank?
        raise "#{actual_fixture_id} does not exist" unless ( @fixtures.keys.include?(actual_fixture_id) || @response_map.keys.include?(actual_fixture_id) )
        raise "#{method} expects actual_xpath as the operation parameter" unless !actual_xpath.blank?

        expected_fixture = @fixtures[expected_fixture_id] || @response_map[expected_fixture_id].try(:resource)
        actual_fixture = @fixtures[actual_fixture_id] || @response_map[actual_fixture_id].try(:resource)

        raise "expected: #{expected_xpath} is not an xpath" unless is_xpath(expected_xpath)
        raise "actual: #{actual_xpath} is not an xpath" unless is_xpath(actual_xpath)
        expected = extract_xpath_value(method, expected_fixture.try(:to_xml), expected_xpath)
        actual = extract_xpath_value(method, actual_fixture.try(:to_xml), actual_xpath)

        return expected, actual
      end

      private

      # Crude method of detecting xpath expressions
      def is_xpath(value)
        value.start_with?("fhir:") && value.include?("@")
      end

      def extract_xpath_value(method, resource_xml, resource_xpath)
        resource_doc = Nokogiri::XML(resource_xml)
        resource_doc.root.add_namespace_definition('fhir', 'http://hl7.org/fhir')
        resource_element = resource_doc.xpath(resource_xpath)

        raise AssertionException.new("#{method} with [#{resource_xpath}] resolved to multiple values instead of a single value", resource_element.to_s) if resource_element.length>1
        resource_element.first.try(:value)
      end

      #
      # def execute_test_method(test_method)
      #   test_item = @testscript.test.select {|t| "#{t.xmlId} #{t.name} test".downcase.tr(' ', '_').to_sym == test_method}.first
      #   result = Crucible::Tests::TestResult.new(test_item.xmlId, test_item.name, Crucible::Tests::BaseTest::STATUS[:skip], '','')
      #   # result.warnings = @warnings  unless @warnings.empty?
      #
      #   result.id = self.object_id.to_s
      #   result.code = test_item.to_xml
      #
      #   result.to_hash.merge!({:test_method => test_method})
      # end

    end
  end
end
