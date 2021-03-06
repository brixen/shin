
RSpec.describe "Language" do
  describe "drop" do
    it "works on lists" do
      expect(%Q{ (print (= '(2 3) (drop 1 '(1 2 3)))) }).to have_output("true")
      expect(%Q{ (print (= '(3)   (drop 2 '(1 2 3)))) }).to have_output("true")
      expect(%Q{ (print (= '()    (drop 3 '(1 2 3)))) }).to have_output("true")
    end

    it "works on vectors" do
      expect(%Q{ (print (= '(2 3) (drop 1 [1 2 3]))) }).to have_output("true")
      expect(%Q{ (print (= '(3)   (drop 2 [1 2 3]))) }).to have_output("true")
      expect(%Q{ (print (= '()    (drop 3 [1 2 3]))) }).to have_output("true")
    end
  end

  describe "take" do
    it "works on lists" do
      expect(%Q{ (print (= '(1)     (take 1 '(1 2 3)))) }).to have_output("true")
      expect(%Q{ (print (= '(1 2)   (take 2 '(1 2 3)))) }).to have_output("true")
      expect(%Q{ (print (= '(1 2 3) (take 3 '(1 2 3)))) }).to have_output("true")
    end

    it "works on vectors" do
      expect(%Q{ (print (= '(1)     (take 1 [1 2 3]))) }).to have_output("true")
      expect(%Q{ (print (= '(1 2)   (take 2 [1 2 3]))) }).to have_output("true")
      expect(%Q{ (print (= '(1 2 3) (take 3 [1 2 3]))) }).to have_output("true")
    end
  end

  describe "take-while" do
    it "works on lists" do
      expect(%Q{
             (print (= '(2 4 6) (take-while even? '(2 4 6 1 3 5))))
             }).to have_output("true")
    end

    it "works on vector" do
      expect(%Q{
             (print (= '(2 4 6) (take-while even? [2 4 6 1 3 5])))
             }).to have_output("true")
    end
  end

  describe "drop-while" do
    it "works on lists" do
      expect(%Q{
             (print (= '(1 3 5) (drop-while even? '(2 4 6 1 3 5))))
             }).to have_output("true")
    end

    it "works on vector" do
      expect(%Q{
             (print (= '(1 3 5) (drop-while even? [2 4 6 1 3 5])))
             }).to have_output("true")
    end
  end

  describe "take-nth" do
    it "works" do
      expect(%Q{
             (print (= '(0 2 4) (take-nth 2 (take 6 (range)))))
             }).to have_output("true")
    end
  end

  describe "partition" do
    it "works" do
      expect(%Q{
             (print (= '([0 1] [2 3] [4 5]) (partition 2 (take 6 (range)))))
             }).to have_output("true")
    end
  end
end

