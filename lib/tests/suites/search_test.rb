module Crucible
  module Tests
    class SearchTest < BaseSuite

      attr_accessor :resource_class
      attr_accessor :conformance
      attr_accessor :searchParams
      attr_reader   :canSearchById

      def execute(resource_class=nil)
        if resource_class
          @resource_class = resource_class
          [{"SearchTest_#{@resource_class.name.demodulize}" => {
            test_file: title,
            tests: execute_test_methods
          }}]
        else
          fhir_resources.map do | klass |
            @resource_class = klass
            {"SearchTest_#{@resource_class.name.demodulize}" => {
              test_file: title,
              tests: execute_test_methods
            }}
          end
        end
      end

      def id
        suffix = resource_class
        suffix = resource_class.name.demodulize if !resource_class.nil?
        "SearchTest_#{suffix}"
      end

      def description
        "Execute suite of searches for #{resource_class.name.demodulize} resources."
      end

      # this allows results to have unique ids for resource based tests
      def result_id_suffix
        resource_class.name.demodulize
      end

      def supplement_test_description(desc)
        "#{desc} #{resource_class.name.demodulize}"
      end

      #
      # Search Test
      # 1. First, get the conformance statement.
      # 2. Lookup the allowed search parameters for each resource.
      # 3. Perform suite of tests against each resource.
      #
      def setup
        if @conformance.nil?
          @conformance = @client.conformanceStatement
        end

        @canSearchById = false

        @conformance.rest.each do |rest|
          rest.resource.each do |resource|
            @searchParams = resource.searchParam if(resource.fhirType.downcase == "#{@resource_class.name.demodulize.downcase}" )
          end
        end

        index = @searchParams.find_index {|item| item.name=="_id" } if !@searchParams.nil?
        @canSearchById = !index.nil?
      end

      test 'S000', 'Compare supported search parameters with specification' do
        metadata {
          define_metadata('search')
        }
        searchParamNames = []
        searchParamNames = @searchParams.map { |item| item.name } if !@searchParams.nil?
        assert ((@resource_class::SEARCH_PARAMS-searchParamNames).size <= 0), 'The server does not support searching all the parameters specified by the specification.'
      end

      #
      # Test the extent of the search capabilities supported.
      # x  no criteria [SE01]
      # x  limit by _count [S003]
      # x  non-existing resource [SE02]
      # x  id [S001,S002]
      # x  parameters [SE03,SE04]
      # x  parameters [SE24,SE25]
      # parameter modifiers (
      # x  :missing, [SE23]
      # :exact,
      # :text,
      # :[type])
      # x  numbers (= >= significant-digits) [SE21,SE22]
      # date (all of the permutations?)
      # token
      # x  quantities [SE21,SE22]
      # x  references [SE05]
      # chained parameters
      # composite parameters
      # text search logical operators
      # tags [TA08], profile, security label
      # _filter parameter
      # result relevance
      # result sorting (_sort parameter)
      # result paging
      # x  _include parameter [SE06]
      # _summary parameter
      # result server conformance (report params actually used)
      # advanced searching with "Query" or _query param (valueset 'expand' and 'validate' queries should be standard)
      #
      test 'S001', 'Search by ID' do
        metadata {
          define_metadata('search')
        }
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              '_id' => '0'
            }
          }
        }
        reply = @client.search(@resource_class, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
      end

      test 'S002', 'Search without search keyword' do
        metadata {
          define_metadata('search')
        }
        options = {
          :search => {
            :flag => false,
            :compartment => nil,
            :parameters => {
              '_id' => '0'
            }
          }
        }
        reply = @client.search(@resource_class, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
      end

      test 'S003', 'Search limit by _count' do
        metadata {
          define_metadata('search')
        }
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              '_count' => '1'
            }
          }
        }
        reply = @client.search(@resource_class, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert (1 >= reply.resource.entry.size), 'The server did not return the correct number of results.'
      end

      # ********************************************************* #
      # _____________________Sprinkler Tests_____________________ #
      # ********************************************************* #

      test 'SE01', 'Search without criteria' do
        metadata {
          links "#{BASE_SPEC_LINK}/#{resource_class.name.demodulize.downcase}.html"
          links "#{REST_SPEC_LINK}#search"
          links "#{REST_SPEC_LINK}#read"
          validates resource: resource_class.name.demodulize, methods: ['read', 'search']
        }
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => nil
          }
        }
        reply = @client.search(@resource_class, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)

        replyB = @client.read_feed(@resource_class)
        assert_equal replyB.resource.total, reply.resource.total, 'Searching without criteria did not return all the results.'
      end


      def define_metadata(method)
        links "#{REST_SPEC_LINK}##{method}"
        links "#{BASE_SPEC_LINK}/#{resource_class.name.demodulize.downcase}.html"
        validates resource: resource_class.name.demodulize, methods: [method]
      end

    end
  end
end
