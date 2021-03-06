defmodule ExUnit.DuplicateTestError do
  defexception [:message]
end

defmodule ExUnit.Case do
  @moduledoc """
  Sets up an ExUnit test case.

  This module must be used in other modules as a way to configure
  and prepare them for testing.

  When used, it accepts the following options:

    * `:async` - configure this specific test case to able to run in parallel
      with other test cases. May be used for performance when this test case
      does not change any global state. Defaults to `false`.

  This module automatically includes all callbacks defined in
  `ExUnit.Callbacks`. See that module's documentation for more
  information.

  ## Examples

       defmodule AssertionTest do
         # Use the module
         use ExUnit.Case, async: true

         # The "test" macro is imported by ExUnit.Case
         test "always pass" do
           assert true
         end
       end

  ## Context

  All tests receive a context as an argument. The context is particularly
  useful for sharing information between callbacks and tests:

      defmodule KVTest do
        use ExUnit.Case

        setup do
          {:ok, pid} = KV.start_link
          {:ok, [pid: pid]}
        end

        test "stores key-value pairs", context do
          assert KV.put(context[:pid], :hello, :world) == :ok
          assert KV.get(context[:pid], :hello) == :world
        end
      end

  As the context is a map, it can be pattern matched on to extract
  information:

      test "stores key-value pairs", %{pid: pid} do
        assert KV.put(pid, :hello, :world) == :ok
        assert KV.get(pid, :hello) == :world
      end

  ## Tags

  The context is used to pass information from the callbacks to
  the test. In order to pass information from the test to the
  callback, ExUnit provides tags.

  By tagging a test, the tag value can be accessed in the context,
  allowing the developer to customize the test. Let's see an
  example:

      defmodule FileTest do
        # Changing directory cannot be async
        use ExUnit.Case, async: false

        setup context do
          # Read the :cd tag value
          if cd = context[:cd] do
            prev_cd = File.cwd!
            File.cd!(cd)
            on_exit fn -> File.cd!(prev_cd) end
          end

          :ok
        end

        @tag cd: "fixtures"
        test "reads UTF-8 fixtures" do
          File.read("hello")
        end
      end

  In the example above, we have defined a tag called `:cd` that is
  read in the setup callback to configure the working directory the
  test is going to run on.

  Tags are also very effective when used with case templates
  (`ExUnit.CaseTemplate`) allowing callbacks in the case template
  to customize the test behaviour.

  Note a tag can be set in two different ways:

      @tag key: value
      @tag :key       # equivalent to setting @tag key: true

  If a tag is given more than once, the last value wins.

  ### Module tags

  A tag can be set for all tests in a module by setting `@moduletag`:

      @moduletag :external

  If the same key is set via `@tag`, the `@tag` value has higher
  precedence.

  ### Known tags

  The following tags are set automatically by ExUnit and are
  therefore reserved:

    * `:case`       - the test case module
    * `:file`       - the file on which the test was defined
    * `:line`       - the line on which the test was defined
    * `:test`       - the test name
    * `:async`      - if the test case is in async mode
    * `:type`       - the type of the test (`:test`, `:property`, etc)
    * `:registered` - used for `ExUnit.Case.register_attribute/3` values
    * `:describe`   - the describe block the test belongs to

  The following tags customize how tests behaves:

    * `:capture_log` - see the "Log Capture" section below
    * `:skip` - skips the test with the given reason
    * `:timeout` - customizes the test timeout in milliseconds (defaults to 60000)
    * `:report` - includes the given tags and context keys on error reports,
      see the "Reporting tags" section

  ### Reporting tags

  ExUnit also allows tags or any other key in your context to be included
  in error reports, making it easy for developers to see under which circumstances
  a test was evaluated. To do so, you use the `:report` tag:

      @moduletag report: [:user_id]

  ## Filters

  Tags can also be used to identify specific tests, which can then
  be included or excluded using filters. The most common functionality
  is to exclude some particular tests from running, which can be done
  via `ExUnit.configure/1`:

      # Exclude all external tests from running
      ExUnit.configure(exclude: [external: true])

  From now on, ExUnit will not run any test that has the `external` flag
  set to `true`. This behaviour can be reversed with the `:include` option
  which is usually passed through the command line:

      mix test --include external:true

  Run `mix help test` for more information on how to run filters via Mix.

  Another use case for tags and filters is to exclude all tests that have
  a particular tag by default, regardless of its value, and include only
  a certain subset:

      ExUnit.configure(exclude: :os, include: [os: :unix])

  Keep in mind that all tests are included by default, so unless they are
  excluded first, the `include` option has no effect.

  ## Log Capture

  ExUnit can optionally suppress printing of log messages that are generated during a test. Log
  messages generated while running a test are captured and only if the test fails are they printed
  to aid with debugging.

  You can opt into this behaviour for individual tests by tagging them with `:capture_log` or enable
  log capture for all tests in the ExUnit configuration:

      ExUnit.start(capture_log: true)

  This default can be overridden by `@tag capture_log: false` or `@moduletag capture_log: false`.

  Since `setup_all` blocks don't belong to a specific test, log messages generated in them (or
  between tests) are never captured. If you want to suppress these messages as well, remove the
  console backend globally:

      config :logger, backends: []
  """

  @reserved [:case, :file, :line, :test, :async, :registered, :describe, :type]

  @doc false
  defmacro __using__(opts) do
    unless Process.whereis(ExUnit.Server) do
      raise "cannot use ExUnit.Case without starting the ExUnit application, " <>
            "please call ExUnit.start() or explicitly start the :ex_unit app"
    end

    quote do
      async = !!unquote(opts)[:async]

      unless Module.get_attribute(__MODULE__, :ex_unit_tests) do
        Enum.each [:ex_unit_tests, :tag, :describetag, :moduletag, :ex_unit_registered],
          &Module.register_attribute(__MODULE__, &1, accumulate: true)

        @before_compile ExUnit.Case
        @after_compile ExUnit.Case
        @ex_unit_async async
        @ex_unit_describe nil
        use ExUnit.Callbacks
      end

      import ExUnit.Callbacks
      import ExUnit.Assertions
      import ExUnit.Case, only: [describe: 2, test: 1, test: 2, test: 3]
      import ExUnit.DocTest
    end
  end

  @doc """
  Defines a test with a string.

  Provides a convenient macro that allows a test to be
  defined with a string. This macro automatically inserts
  the atom `:ok` as the last line of the test. That said,
  a passing test always returns `:ok`, but, more importantly,
  it forces Elixir to not tail call optimize the test and
  therefore avoids hiding lines from the backtrace.

  ## Examples

      test "true is equal to true" do
        assert true == true
      end

  """
  defmacro test(message, var \\ quote(do: _), contents) do
    contents =
      case contents do
        [do: block] ->
          quote do
            unquote(block)
            :ok
          end
        _ ->
          quote do
            try(unquote(contents))
            :ok
          end
      end

    var      = Macro.escape(var)
    contents = Macro.escape(contents, unquote: true)

    quote bind_quoted: [var: var, contents: contents, message: message] do
      name = ExUnit.Case.register_test(__ENV__, :test, message, [])
      def unquote(name)(unquote(var)), do: unquote(contents)
    end
  end

  @doc """
  Defines a not implemented test with a string.

  Provides a convenient macro that allows a test to be
  defined with a string, but not yet implemented. The
  resulting test will always fail and print "Not yet
  implemented" error message. The resulting test case is
  also tagged with :not_implemented.

  ## Examples

      test "this will be a test in future"

  """
  defmacro test(message) do
    quote bind_quoted: binding() do
      name = ExUnit.Case.register_test(__ENV__, :test, message, [:not_implemented])
      def unquote(name)(_), do: flunk("Not yet implemented")
    end
  end

  @doc """
  Describes tests together.

  Every describe block receives a name which is used as prefix for
  upcoming tests. Inside a block, `ExUnit.Callbacks.setup/1` may be
  invoked and it will define a setup callback to run only for the
  current block. The describe name is also added as a tag, allowing
  developers to run tests for specific blocks.

  ## Examples

      defmodule StringTest do
        use ExUnit.Case, async: true

        describe "String.capitalize/1" do
          test "first grapheme is in uppercase" do
            assert String.capitalize("hello") == "Hello"
          end

          test "converts remaining graphemes to lowercase" do
            assert String.capitalize("HELLO") == "Hello"
          end
        end
      end

  When using Mix, you can run all tests in a describe block as:

      mix test --only describe:"String.capitalize/1"

  Note describe blocks cannot be nested. Instead of relying on hierarchy
  for composition, developers should build on top of named setups. For
  example:

      defmodule UserManagementTest do
        use ExUnit.Case, async: true

        describe "when user is logged in and is an admin" do
          setup [:log_user_in, :set_type_to_admin]

          test ...
        end

        describe "when user is logged in and is a manager" do
          setup [:log_user_in, :set_type_to_manager]

          test ...
        end

        defp log_user_in(context) do
          # ...
        end
      end

  By forbidding hierarchies in favor of named setups, it is straight-forward
  for the developer to glance at each describe block and know exactly the
  setup steps involved.
  """
  defmacro describe(message, do: block) do
    quote do
      if @ex_unit_describe do
        raise "cannot call describe/2 inside another describe. See the documentation " <>
              "for describe/2 on named setups and how to handle hierarchies"
      end

      @ex_unit_describe (case unquote(message) do
        msg when is_binary(msg) -> msg
        msg -> raise ArgumentError, "describe name must be a string, got: #{inspect msg}"
      end)
      Module.delete_attribute(__ENV__.module, :describetag)

      try do
        unquote(block)
      after
        @ex_unit_describe nil
        Module.delete_attribute(__ENV__.module, :describetag)
      end
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      def __ex_unit__(:case) do
        %ExUnit.TestCase{name: __MODULE__, tests: @ex_unit_tests}
      end
    end
  end

  @doc false
  def __after_compile__(%{module: module}, _) do
    if Module.get_attribute(module, :ex_unit_async) do
      ExUnit.Server.add_async_case(module)
    else
      ExUnit.Server.add_sync_case(module)
    end
  end

  @doc """
  Registers a function to run as part of this case.

  This is used by 3rd party projects, like QuickCheck, to
  implement macros like `property/3` that works like `test`
  but instead defines a property. See `test/3` implementation
  for an example of invoking this function.

  The test type will be converted to a string and pluralized for
  display. You can use `ExUnit.plural_rule/2` to set a custom
  pluralization.
  """
  def register_test(%{module: mod, file: file, line: line}, type, name, tags) do
    moduletag = Module.get_attribute(mod, :moduletag)

    unless moduletag do
      raise "cannot define #{type}. Please make sure you have invoked " <>
            "\"use ExUnit.Case\" in the current module"
    end

    registered_attributes = Module.get_attribute(mod, :ex_unit_registered)
    registered = Map.new(registered_attributes, &{&1, Module.get_attribute(mod, &1)})

    tag = Module.delete_attribute(mod, :tag)
    async = Module.get_attribute(mod, :ex_unit_async)

    {name, describe, describetag} =
      if describe = Module.get_attribute(mod, :ex_unit_describe) do
        {:"#{type} #{describe} #{name}", describe, Module.get_attribute(mod, :describetag)}
      else
        {:"#{type} #{name}", nil, []}
      end

    if Module.defines?(mod, {name, 1}) do
      raise ExUnit.DuplicateTestError, ~s("#{name}" is already defined in #{inspect mod})
    end

    tags =
      (tags ++ tag ++ describetag ++ moduletag)
      |> normalize_tags
      |> validate_tags
      |> Map.merge(%{line: line, file: file, registered: registered,
                     async: async, describe: describe, type: type})

    test = %ExUnit.Test{name: name, case: mod, tags: tags}
    Module.put_attribute(mod, :ex_unit_tests, test)

    Enum.each registered_attributes, fn(attribute) ->
      Module.delete_attribute(mod, attribute)
    end

    name
  end

  @doc """
  Registers a new attribute to be used during `ExUnit.Case` tests.

  The attribute values will be available as a key/value pair in
  `context.registered`. The key/value pairs will be cleared
  after each `ExUnit.Case.test/3` similar to `@tag`.

  `Module.register_attribute/3` is used to register the attribute,
  this function takes the same options.

  ## Examples

      defmodule MyTest do
        use ExUnit.Case
        ExUnit.Case.register_attribute __ENV__, :foobar

        @foobar hello: "world"
        test "using custom test attribute", context do
          assert context.registered.hello == "world"
        end
      end
  """
  def register_attribute(env, name, opts \\ [])

  def register_attribute(%{module: module}, name, opts) do
    register_attribute(module, name, opts)
  end

  def register_attribute(mod, name, opts) when is_atom(mod) and is_atom(name) and is_list(opts) do
    Module.register_attribute(mod, name, opts)
    Module.put_attribute(mod, :ex_unit_registered, name)
  end

  defp validate_tags(tags) do
    for tag <- @reserved,
        Map.has_key?(tags, tag) do
      raise "cannot set tag #{inspect tag} because it is reserved by ExUnit"
    end

    unless is_atom(tags[:type]),
      do: raise "value for tag `:type` must be an atom"

    tags
  end

  defp normalize_tags(tags) do
    Enum.reduce Enum.reverse(tags), %{}, fn
      tag, acc when is_atom(tag) -> Map.put(acc, tag, true)
      tag, acc when is_list(tag) -> tag |> Enum.into(acc)
    end
  end
end
