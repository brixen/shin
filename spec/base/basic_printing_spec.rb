
RSpec.describe "Language", "basic printing" do
  it "tests output correctly (positive)" do
    expect(%Q{(print "Hello")}).to have_output("Hello")
  end

  it "tests output correctly (negative)" do
    expect(%Q{}).not_to have_output("Hello")
  end

  it "tests output correctly (multiple calls)" do
    expect(%Q{
           (print "Hello")
           (print "dear")
           (print "world")
           }).to have_output("Hello dear world")
  end

  it "tests output correctly (multiple args)" do
    expect(%Q{
           (print "Hello" "dear" "world")
           }).to have_output("Hello dear world")
  end
end
