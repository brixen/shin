
require 'shin/ast'
require 'shin/js_context'
require 'shin/fast_mutator'

module Shin
  # Applies transformations to the Shin AST
  # These might include:
  #   - Macro expansions
  #   - Desugaring
  #   - Optimizations
  class Mutator
    DEBUG = ENV['MUTATOR_DEBUG']
    USE_FAST = ENV['LEGACY_MUTATOR'] != "1"

    include Shin::AST

    attr_reader :mod
    @@sym_seed = 2121

    def initialize(compiler, mod)
      @compiler = compiler
      @mod = mod
      @seed = 0
      @expands = 0
      @fast_mutator = FastMutator.new(@compiler, @mod, js_context)
    end

    def mutate
      if mod.mutating
        # FIXME oh god this is a terrible workaround.
        mod.ast2 = mod.ast
        return
      end

      debug "Mutating #{mod.slug}"
      mod.mutating = true
      mod.ast2 = mod.ast.map { |x| expand(x) }

      # we've probably been generating ourselves while mutating, so null those
      # so that the compiler doesn't over-cache things.
      mod.jst = nil
      mod.code = nil
    end

    protected

    def expand(node)
      case node
      when List
        first = node.inner.first
        case first
        when Symbol
          invoc = node
          info = resolve_macro(first.value)
          if info
            expanded_ast = nil

            if USE_FAST
              expanded_ast = @fast_mutator.expand(invoc, info)
            else
              eval_mod = make_macro_module(invoc, info)
              debug "========== [Mutator] ======================="
              debug "; Macro :\n#{info[:macro]}\n\n" if DEBUG

              debug "; Original AST:\n#{invoc}\n\n" if DEBUG
              expanded_ast = eval_macro_module(eval_mod)
            end

            @expands += 1
            node = expand(expanded_ast)
          end
        end
      end

      if Sequence === node
        inner = node.inner
        index = 0
        inner.each do |child|
          poster_child = expand(child)
          inner = inner.set(index, poster_child) if poster_child != child
          index += 1
        end

        if inner != node.inner
          node = node.class.new(node.token, inner)
        end
      end

      node
    end

    def resolve_macro(name)
      @mod.requires.each do |req|
        next unless req.macro?

        dep = @compiler.modules[req]

        # compile macro code if needed
        unless dep.code
          Shin::NsParser.new(dep).parse
          Shin::Mutator.new(@compiler, dep).mutate
          Shin::Translator.new(@compiler, dep).translate
          Shin::Generator.new(dep).generate
          @compiler.modules << dep
          # debug "Generated macro code from #{dep.slug}"
        end

        res = dep.scope.form_for(name)
        if res
          # debug "Found '#{name}' in #{dep.slug}, which has defs #{defs.keys.join(", ")}" if DEBUG
          return {:macro => res, :module => dep}
        end
      end

      nil
    end

    def make_macro_module(invoc, info)
      # debug "Making macro_eval module for #{@mod.slug}"

      t = invoc.token
      macro_sym = invoc.inner.first

      eval_mod = Shin::Module.new
      eval_mod.macro = true
      _yield = Symbol.new(t, "yield")
      pr_str = Symbol.new(t, "pr-str")

      eval_args = Hamster.vector(macro_sym)
      invoc.inner.drop(1).each do |arg|
        eval_args <<= SyntaxQuote.new(arg.token, arg)
      end
      eval_node = List.new(t, eval_args)

      eval_ast = List.new(t, Hamster.vector(_yield, List.new(t, Hamster.vector(pr_str, eval_node))))
      eval_mod.ast = eval_mod.ast2 = [eval_ast]

      unless info[:module].core?
        info_ns = info[:module].ns
        req = Shin::Require.new(info_ns, :macro => true, :refer => :all)
        eval_mod.requires << req
      end

      eval_mod.source = @mod.source
      Shin::NsParser.new(eval_mod).parse
      Shin::Translator.new(@compiler, eval_mod).translate
      Shin::Generator.new(eval_mod).generate

      deps = @compiler.collect_deps(eval_mod)

      deps.each do |slug, dep|
        next if slug == eval_mod.ns
        Shin::NsParser.new(dep).parse unless dep.ns
        Shin::Mutator.new(@compiler, dep).mutate unless dep.ast2
        Shin::Translator.new(@compiler, dep).translate unless dep.jst
        Shin::Generator.new(dep).generate unless dep.code
      end

      eval_mod
    end

    def eval_macro_module(eval_mod)
      js = js_context

      result = nil
      js.context['yield'] = lambda do |_, ast_back|
        result = ast_back
      end
      begin
        js.load(eval_mod.code, :inline => true)
      rescue => e
        puts "While trying to load:\n\n#{eval_mod.code}\n\n"
        raise e
      end

      res_parser = Shin::Parser.new(result.to_s)
      expanded_ast = res_parser.parse.first
      debug "; Expanded AST:\n#{expanded_ast}\n\n" if DEBUG

      dequoted_ast = dequote(expanded_ast)
      debug "; Dequoted AST:\n#{dequoted_ast}\n\n" if DEBUG

      dequoted_ast
    end

    def js_context
      unless @js_context
        js = @js_context = Shin::JsContext.new
        js.context['debug'] = lambda do |_, *args|
          debug "[from JS] #{args.join(" ")}"
        end

        js.providers << @compiler
      end
      @js_context
    end

    def dequote(node)
      case node
      when Sequence
        inner = node.inner

        offset = 0
        index = 0
        inner.each do |child|
          poster_child = dequote(child)
          if poster_child != child
            case poster_child
            when Hamster::Vector
              inner = inner.delete_at(index + offset)
              offset -= 1
              poster_child.each do |el|
                offset += 1
                inner = inner.insert(index + offset, el)
              end
            when nil
              inner = inner.delete_at(index + offset)
              offset -= 1
            else
              inner = inner.set(index + offset, poster_child)
            end
          end
          index += 1
        end

        if node.inner == inner
          node
        else
          node.class.new(node.token, inner)
        end
      when Unquote
        if Deref === node.inner
          deref = node.inner

          case
          when Sequence === deref.inner
            deref.inner.inner.map { |x| dequote(x) }
          when deref.inner.sym?("nil")
            nil
          else
            ser!("Cannot use splicing on non-list form #{deref.inner}")
          end

        else
          dequote(node.inner)
        end
      else
        node
      end
    end

    def fresh
      @seed += 1
    end

    def self.fresh_sym
      @@sym_seed += 1
    end

    def debug(*args)
      puts("[MUTATOR] #{args.join(" ")}") if DEBUG
    end

    def ser!(msg)
      raise msg
    end
  end
end

