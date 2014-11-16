
require 'therubyracer'
require 'oj'

module Shin
  class JsContext

    DEBUG = false

    attr_reader :file_provider
    attr_reader :providers

    def initialize
      @context = V8::Context.new
      @seed = 0

      @file_provider = FileJsProvider.new
      @file_provider.sourcepath << File.expand_path("../js", __FILE__)
      @providers = [@file_provider]

      @context.eval %Q{
        this.$kir = {
          modules: {},

          define: function (name, deps, factory) {
            return $kir.modules[name] = {
              deps: deps,
              factory: factory,
              exports: {}
            };
          }
        }
      }
    end

    def context
      @context
    end

    def eval(source)
      @context.eval(source)
    end

    def spec_loaded?(spec)
      @context.eval("$kir.modules[#{escape(spec.name)}] != null")
    end

    def fresh_seed
      @seed += 1
    end

    def load(spec_input, inline: false)
      spec = if inline
        parse_spec("anon_#{fresh_seed}")
      else
        parse_spec(spec_input)
      end

      debug "Loading #{spec.name}"

      if spec.text?
        text_content = File.read(resource_path(spec.name))
        @context.eval %Q{
          $kir.define(#{escape(spec.name)}, [], null).exports = #{escape(text_content)};
        }
        return
      end

      # use globals so we can use V8::Context.load
      # and retain stack trace information.
      # the alternative is to eval the code, but
      # it makes debugging a lot harder.
      
      @context.eval %Q{
        this.$define_called = false;
        this.define = function (a, b, c) {
          $define_called = true; 
          if (typeof a === 'function') {
            $kir.define(#{escape(spec.name)}, [], a);
          } else if (typeof a === 'string') {
            $kir.define(a, b, c);
          } else {
            $kir.define(#{escape(spec.name)}, a, b);
          }
        }
        this.define.amd = true;
      }

      if inline
        @context.eval spec_input
      else
        done = false
        name = spec.name + ".js"
        @providers.each do |provider|
          res = provider.provide_js_module(name)
          case res
          when nil
            next
          when Pathname
            debug "Loading from pathname #{name} -> #{res}"
            @context.load res.to_s
            done = true
          else
            debug "Evaling from memory #{name}"
            @context.eval res
            done = true
          end
        end
        throw "JS file not found: #{spec.name}" unless done
      end

      mod = @context.eval %Q{
        var name = #{escape(spec.name)};

        if (!$define_called) {
          $kir.define(name, [], null);
        }

        delete this.$define_called;
        delete this.define;
        $kir.modules[name];
      }

      if mod[:factory].nil?
        debug "#{spec.name} doesn't look AMD-ready."

        # we have no factory to run.
        return
      end

      js = []
      js << "var deps = ["

      uses_exports = false

      mod[:deps].each do |dep|
        dep_spec = parse_spec(dep)
        if dep_spec.exports?
          uses_exports = true
          js << "$kir.modules[#{escape(spec.name)}].exports, "
        elsif dep_spec.name == 'require'
          # workaround for hamt
          debug "#{spec.name} => require hack"
          js << "null, "
        else
          debug "#{spec.name} => #{dep_spec.name}"
          unless spec_loaded?(dep_spec)
            load(dep_spec.input)
          end
          js << "$kir.modules[#{escape(dep_spec.name)}].exports, "
        end
      end
      js << "];"

      js << "var result = $kir.modules[#{escape(spec.name)}].factory.apply(null, deps);"

      # not requesting 'exports' and just returning an object
      # is valid AMD apparently. It won't work with circular 
      # references but whatever.
      unless uses_exports
        js << "$kir.modules[#{escape(spec.name)}].exports = result;"
      end

      # actually call the factory!
      debug "Calling the factory of #{spec.name}"
      @context.eval js.join("\n")

    end

    def resource_path(name)
      File.expand_path("../js/#{name}", __FILE__)
    end

    def escape(input)
      Oj.dump(input)
    end

    def set(key, val)
      @context[key] = val
    end

    def context
      @context
    end

    private

    def parse_spec(spec_input)
      _, text, _, name = /^(text!)?(\.\/)?(.*)$/.match(spec_input).to_a
      Struct.
        new(:input, :name, :exports?, :text?).
        new(spec_input, name, name == 'exports', !!text)
    end

    def debug(*args)
      puts(*args) if DEBUG
    end

  end

  class FileJsProvider
    attr_reader :sourcepath

    def initialize(sourcepath = [])
      @sourcepath = sourcepath
    end

    def provide_js_module(name)
      @sourcepath.each do |sp|
        path = Pathname.new("#{sp}/#{name}")
        return path if path.exist?
      end
      nil
    end
  end
end

