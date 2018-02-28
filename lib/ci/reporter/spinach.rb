
require 'spinach'
require 'time'
require 'builder'
require 'ci/reporter/output_capture'

module CI
  module Reporter
    module StructureXmlHelpers
      # Struct#to_h is not available in Ruby 1.9
      def attr_hash
        Hash[self.members.zip(self.values)]
      end

      # Removes empty attributes and truncates long attributes.
      def cleaned_attributes
        attr_array = attr_hash
          .reject {|k,v| v.to_s.empty? }
          .map    {|k,v| [k, truncate_at_newline(v)] }
        Hash[attr_array]
      end

      def truncate_at_newline(txt)
        txt.to_s.sub(/\n.*/m, '...')
      end
    end

    # Basic structure representing the running of a test suite.  Used to time tests and store results.
    class TestSuite < Struct.new(:name, :tests, :time, :failures, :errors, :skipped, :assertions, :timestamp)
      include StructureXmlHelpers

      attr_accessor :testcases
      attr_accessor :stdout, :stderr
      def initialize(name)
        super(name.to_s) # RSpec passes a "description" object instead of a string
        @testcases = []
        @capture_out = nil
        @capture_err = nil
      end

      # Starts timing the test suite.
      def start
        @start = Time.now
        unless ENV['CI_CAPTURE'] == "off"
          @capture_out = OutputCapture.wrap($stdout) {|io| $stdout = io }
          @capture_err = OutputCapture.wrap($stderr) {|io| $stderr = io }
        end
      end

      # Finishes timing the test suite.
      def finish
        self.tests = testcases.size
        self.time = Time.now - @start
        self.timestamp = @start.iso8601
        self.failures = testcases.map(&:failure_count).reduce(&:+)
        self.errors = testcases.map(&:error_count).reduce(&:+)
        self.skipped = testcases.count(&:skipped?)
        self.stdout = @capture_out.finish if @capture_out
        self.stderr = @capture_err.finish if @capture_err
      end

      # Creates an xml string containing the test suite results.
      def to_xml
        builder = Builder::XmlMarkup.new(indent: 2)
        builder.instruct!
        builder.testsuite(cleaned_attributes) do
          @testcases.each do |tc|
            tc.to_xml(builder)
          end
          unless self.stdout.to_s.empty?
            builder.tag! "system-out" do
              builder.text!(self.stdout)
            end
          end
          unless self.stderr.to_s.empty?
            builder.tag! "system-err" do
              builder.text!(self.stderr)
            end
          end
        end
      end
    end

    # Structure used to represent an individual test case.  Used to time the test and store the result.
    class TestCase < Struct.new(:name, :time, :assertions)
      include StructureXmlHelpers

      attr_accessor :failures
      attr_accessor :skipped

      def initialize(*args)
        super
        @failures = []
      end

      # Starts timing the test.
      def start
        @start = Time.now
      end

      # Finishes timing the test.
      def finish
        self.time = Time.now - @start
      end

      # Returns non-nil if the test failed.
      def failure?
        failures.any?(&:failure?)
      end

      # Returns non-nil if the test had an error.
      def error?
        failures.any?(&:error?)
      end

      def failure_count
        failures.count(&:failure?)
      end

      def error_count
        failures.count(&:error?)
      end

      def skipped?
        skipped
      end

      # Writes xml representing the test result to the provided builder.
      def to_xml(builder)
        builder.testcase(cleaned_attributes) do
          if skipped?
            builder.skipped
          else
            failures.each do |failure|
              tag = failure.error? ? :error : :failure

              builder.tag!(tag, type: truncate_at_newline(failure.name), message: truncate_at_newline(failure.message)) do
                builder.text!(failure.message + " (#{failure.name})\n")
                builder.text!(failure.location)
              end
            end
          end
        end
      end
    end
  end
end

require 'ci/reporter/report_manager'
require 'ci/reporter/spinach/version'


module CI
  module Reporter
    class Spinach < ::Spinach::Reporter
      include SpinachVersion

      def initialize(options = nil)
        @options = options
        @report_manager = ReportManager.new('features')
      end

      def generate_name(item)
        uid = item.tags.select{|x| x.start_with?('uid') }.first.gsub("-", ":")
        name = item.is_a?(Hash) ? item['name'] : item.name

        "#{name} (#{uid})"
      end

      def before_feature_run(feature)
        @test_suite = TestSuite.new(generate_name(feature))
        @test_suite.start
      end

      def before_scenario_run(scenario, step_definitions = nil)
        @test_case = TestCase.new(generate_name(scenario))
        @test_case.start
      end

      def on_undefined_step(step, failure, step_definitions = nil)
        @test_case.failures << SpinachFailure.new(:error, step, failure, nil)
      end

      def on_failed_step(step, failure, step_location, step_definitions = nil)
        @test_case.failures << SpinachFailure.new(:failed, step, failure, step_location)
      end

      def on_error_step(step, failure, step_location, step_definitions = nil)
        @test_case.failures << SpinachFailure.new(:error, step, failure, step_location)
      end

      def after_scenario_run(scenario, step_definitions = nil)
        @test_case.finish
        @test_suite.testcases << @test_case
        @test_case = nil
      end

      def after_feature_run(feature)
        @test_suite.finish
        @report_manager.write_report(@test_suite)
        @test_suite = nil
      end
    end

    class SpinachFailure
      def initialize(type, step, failure, step_location)
        @type = type
        @step = step
        @failure = failure
        @step_location = step_location
      end

      def failure?
        @type == :failed
      end

      def error?
        @type == :error
      end

      def name
        @failure.class.name
      end

      def message
        @failure.message
      end

      def location
        @failure.backtrace.join("\n")
      end
    end
  end
end

class Spinach::Reporter
  CiReporter = ::CI::Reporter::Spinach
end
