
RSpec.describe "Compiler" do
  it "tests output correctly" do
    expect(%Q{
           (print "Hello")
           }).to have_output("Hello")
  end

  it "tests output correctly (negative)" do
    expect(%Q{}).not_to have_output("Hello")
  end

  it "defines and calls a simple function" do
    expect(%Q{
           (defn hello [] (print "Hello"))
           (hello)
           }).to have_output("Hello")
  end
end
