require 'ci/reporter/core'
require 'ci/reporter/spinach/version'
require 'spinach'

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
