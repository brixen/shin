
RSpec.describe "Language", "literals" do

  it "has working string literals" do
    expect(%Q{(print "hello")}).to have_output "hello"
  end

  it "has working regexp literals" do
    # bit of a hack there (relies on JS RegExp instances)
    # .. but not sure how else to check for it.
    expect(%q{(print (.-source #"hello"))}).to have_output "hello"
  end

  it "has working symbol literals" do
    expect(%q{(print (name 'money!))}).to have_output "money!" 
  end

  it "has working keyword literals" do
    expect(%q{(print (name :avada-kedavra))}).to have_output "avada-kedavra" 
  end

  it "has working list literals" do
    expect(%q{(print (first '("perry" "cox")))}).to have_output "perry"
  end

  it "has working vector literals" do
    expect(%q{(print (last ["perry" "cox"]))}).to have_output "cox"
  end

  it "has working set literals" do
    expect(%q{(print (contains? #{:a :b :c} :b))}).to have_output "true"
  end

  it "has working map literals" do
    expect(%q{(print (get {:a 42} :a))}).to have_output "42"
  end

end

