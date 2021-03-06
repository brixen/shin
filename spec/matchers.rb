
require 'shin/js_context'
require 'shin/compiler'
require 'shin/parser'
require 'shin/utils/matcher'
require 'shin/utils/global_cache'

include Shin::Utils::Matcher
include Shin::Utils::GlobalCache

RSpec::Matchers.define :ast_match do |pattern|

  match do |actual|
    Shin::Utils::Matcher.send(:matches?, Shin::Parser.parse(actual), pattern) 
  end

  failure_message do |actual|
    "expected '#{actual}' to match AST pattern '#{pattern}'"
  end

  failure_message_when_negated do |actual|
    "expected '#{actual}' not to match AST pattern '#{pattern}'"
  end
end

# cache = Shin::ModuleCache.new
js = Shin::JsContext.new
js.context['debug'] = lambda do |_, *args|
  puts "[debug] #{args.join(" ")}"
end

RSpec::Matchers.define :have_output do |expected_output|
  output = []
  code = nil

  match do |actual|
    source = nil
    macros = nil
    case actual
    when String
      source = actual
    else
      source = actual[:source]
      macros = actual[:macros]
    end

    compiler = Shin::Compiler.new(:cache => global_cache)
    res = compiler.compile(source, :macros => macros)

    js.providers << compiler
    js.context['print'] = lambda do |_, *args|
      output << args.join(" ")
    end
    code = res.code
    js.load(code, :inline => true)
    js.providers.delete(compiler)

    if Array === expected_output
      output === expected_output
    else
      output.join(" ") === expected_output
    end
  end

  failure_message do |actual|
    case expected_output
    when Array
      s = "mismatches:\n"
      l1 = expected_output.length
      l2 = output.length
      s << " - wrong length, (expected #{l1}, got #{l2})\n" unless l1 == l2
      (0...[l1, l2].min).each do |i|
        e = expected_output[i]
        g = output[i]
        s << " - at #{i}, expected #{e}, got #{g}\n" unless e == g
      end
      s
    else
      "expected output '#{expected_output}', got '#{output.join(" ")}'"
    end + (ENV['MATCHERS_DEBUG'] ? ", JS code:\n#{code}" : "")
  end
end

