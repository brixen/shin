
require 'shin/jst'
require 'shin/ast'
require 'shin/utils'

module Shin
  # Converts Shin AST to JST
  class Translator
    include Shin::Utils::LineColumn
    include Shin::Utils::Snippet
    include Shin::Utils::Matcher
    include Shin::Utils::Mangler
    include Shin::JST

    def initialize(p_input, options)
      @input = p_input.dup
      @options = options
    end

    def translate(ast)
      requires = %w(exports shin mori)

      program = Program.new
      load_shim = FunctionExpression.new
      load_shim.params << make_ident('root');
      load_shim.params << make_ident('factory')
      load_shim.body = BlockStatement.new
      define_call = CallExpression.new(make_ident('define'))
      require_arr = ArrayExpression.new
      requires.each do |req|
        require_arr.elements << make_literal(req)
      end
      define_call.arguments << require_arr
      define_call.arguments << make_ident('factory')
      load_shim.body.body << ExpressionStatement.new(define_call)

      factory = FunctionExpression.new
      requires.each do |req|
        factory.params << make_ident(req)
      end
      factory.body = BlockStatement.new

      shim_call = CallExpression.new(load_shim)
      shim_call.arguments << ThisExpression.new
      shim_call.arguments << factory
      program.body << ExpressionStatement.new(shim_call)

      body = factory.body.body
      shin_init = MemberExpression.new(make_ident('shin'), make_ident('init'), false)
      init_call = CallExpression.new(shin_init)
      init_call.arguments << make_ident('this')
      init_call.arguments << make_literal('shin_module')
      body << ExpressionStatement.new(init_call)

      ast.each do |node|
        case
        when matches?(node, "(defn :expr*)")
          body << translate_defn(node.inner.drop 1)
        when matches?(node, "(def :expr*)")
          body << translate_def(node.inner.drop 1)
        when matches?(node, ":expr")
          # any expression is a statement, after all.
          expr = translate_expr(node) or ser!("Couldn't parse expr", node)
          body << ExpressionStatement.new(expr)
        else
          ser!("Unknown form in Program", node)
        end
      end

      program
    end

    protected

    def translate_let(list)
      matches?(list, "[] :expr*") do |bindings, exprs|
        anon = FunctionExpression.new
        call = CallExpression.new(anon)

        ser!("Invalid let form: odd number of binding forms", list) unless bindings.inner.length.even?
        bindings.inner.each_slice(2) do |binding|
          name, val = binding

          case name
          when Shin::AST::Sequence
            ser!("Destructuring isn't supported yet.", name)
          when Shin::AST::Symbol
            # all good
          else
            ser!("Invalid let form: first binding form should be a symbol or collection", name)
          end

          anon.params << make_ident(name.value)
          call.arguments << translate_expr(val)
        end

        anon.body = BlockStatement.new
        translate_body_into_block(exprs, anon.body)
        return call
      end or ser!("Invalid let form", list)
    end

    def translate_def(list)
      matches?(list, ":sym :expr*") do |name, rest|
        decl = VariableDeclaration.new
        dtor = VariableDeclarator.new(make_ident(name.value))

        case
        when matches?(rest, ":str :expr")
          doc, expr = rest
          dtor.init = translate_expr(expr)
        when matches?(rest, ":expr")
          expr = rest.first
          dtor.init = translate_expr(expr)
        else
          ser!("Invalid def form", list)
        end

        decl.declarations << dtor
        return decl
      end or ser!("Invalid def form", list)
    end

    def translate_defn(list)
      matches?(list, ":sym :str? [:sym*] :expr*") do |name, doc, args, body|
        decl = FunctionDeclaration.new(make_ident(name.value))
        args.inner.each do |arg|
          decl.params << make_ident(arg.value)
        end

        decl.body = block = BlockStatement.new
        translate_body_into_block(body, block)
        return decl
      end or ser!("Invalid defn form", list)
    end

    def translate_fn(list)
      matches?(list, "[:sym*] :expr*") do |args, body|
        expr = FunctionExpression.new
        args.inner.each do |arg|
          expr.params << make_ident(arg.value)
        end

        expr.body = BlockStatement.new
        translate_body_into_block(list.drop(1), expr.body)
        return expr
      end or ser!("Invalid fn form", list)
    end

    def translate_body_into_block(body, block)
      inner_count = body.length
      body.each_with_index do |expr, i|
        node = translate_expr(expr)
        last = (inner_count - 1 == i)
        block.body << (last ? ReturnStatement : ExpressionStatement).new(node)
      end
    end

    def translate_expr(expr)
      case expr
      when Shin::AST::Symbol
        return make_ident(expr.value)
      when Shin::AST::RegExp
        return NewExpression.new(make_ident("RegExp"), [make_literal(expr.value)])
      when Shin::AST::Literal
        return make_literal(expr.value)
      when Shin::AST::Deref
        t = expr.token
        return translate_expr(Shin::AST::List.new(t, [Shin::AST::Symbol.new(t, "deref"), expr.inner]))
      when Shin::AST::List
        list = expr.inner
        first = list.first
        case
        when Shin::AST::MethodCall === first
          property = translate_expr(list[0].id)
          object = translate_expr(list[1])
          mexp = MemberExpression.new(object, property, false)
          call = CallExpression.new(mexp)
          list.drop(2).each do |arg|
            call.arguments << translate_expr(arg)
          end
          return call
        when first.sym?("let")
          return translate_let(list.drop(1))
        when first.sym?("fn")
          return translate_fn(list.drop(1))
        when first.sym?("do")
          anon = FunctionExpression.new
          anon.body = BlockStatement.new
          translate_body_into_block(list.drop(1), anon.body)
          return CallExpression.new(anon)
        when first.sym?("if")
          anon = FunctionExpression.new
          anon.body = BlockStatement.new
          body = anon.body.body

          test, consequent, alternate = list.drop 1
          fi = IfStatement.new(translate_expr(test))
          fi.consequent  = BlockStatement.new
          translate_body_into_block([consequent], fi.consequent)
          fi.alternate = BlockStatement.new
          translate_body_into_block([alternate], fi.alternate)
          body << fi

          return CallExpression.new(anon)
        else
          # function call
          call = CallExpression.new(translate_expr(first))
          list.drop(1).each do |arg|
            call.arguments << translate_expr(arg)
          end
          return call
        end
      else
        ser!("Unknown expr form #{expr}", expr.token)
        nil
      end
    end

    def make_literal(id)
      Literal.new(id)
    end

    def make_ident(id)
      Identifier.new(mangle(id))
    end

    def file
      @options[:file] || "<stdin>"
    end

    def ser!(msg, token)
      token = token.to_a.first if token.respond_to?(:to_a)
      token = token.token if Shin::AST::Node === token
      token = nil unless Shin::AST::Token === token

      start  = token ? token.start  : 0
      length = token ? token.length : 1

      line, column = line_column(@input, start)
      snippet = snippet(@input, start, length)

      raise "#{msg} at #{file}:#{line}:#{column}\n\n#{snippet}\n\n"
    end
  end
end
