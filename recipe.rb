require 'yaml'

#TODOs
# * talk about specific resources when listing steps
# * gate resources on temp (eg) instead of just count
# * bucket times into 5 minutes
# * pretty print times
# * implement count

KITCHEN = "terrykitchen"
MEAL = "martha"

def banner(str)
  puts "*" * 80
  puts "  #{str}  ".upcase.center(80, "*")
  puts "*" * 80
end

class Meal
  attr_reader :recipes

  def initialize(meals)
    @recipes = Hash[*meals.map{|k, v| [k, Recipe.new(k, v)]}.flatten]
  end
end

class Recipe
  attr_accessor :name, :notes, :ingredients, :steps, :buffer

  def time
    self.steps.reduce{|sum, step| sum + step.time}
  end

  def initialize(name, info)
    self.name = name
    self.notes = info['notes']
    self.ingredients = info['ingredients']
    self.steps = info['steps'].map{|s| Step.new(s)}
    self.buffer = info['buffer'].to_i
  end
end

class Step
  attr_accessor :name, :resources, :time, :stop, :parallel

  def initialize(step_hash)
    self.name = step_hash['name']
    self.resources = step_hash['resources']
    self.time = step_hash['time'].to_i
    self.stop = step_hash['stop']
    self.parallel = step_hash['parallel']
  end

  def parallel?
    !!self.parallel
  end

  def stop?
    !!self.stop
  end

  def needs_anything?
    !self.resources.nil?
  end

  def to_s
    self.name.to_s
  end

  def stop_string
    "STOP #{to_s}"
  end
end

class Kitchen
  def initialize(resources)
    @resources = resources.map{|info| (1..info['count']).map{Resource.new(info['name'])}}.flatten
  end

  def available?(resource_name, start, stop)
    return true if resource_name.nil?
    @resources.select{|r| r.name == resource_name}.detect{|r| r.available?(start, stop)}
  end

  def claim!(resource_name, start, stop)
    return true if resource_name.nil?
    available?(resource_name, start, stop).claim!(start, stop)
  end

  def plan!(meal)
    steps = plan(meal)
    steps.keys.sort.each do |time|
      puts
      puts "T #{pretty time.to_i} minutes"
      steps[time].each do |step|
        puts "* #{step}"
      end
    end
  end

  def pretty(time)
    "-#{time.abs / 60}h#{time.abs % 60}m"
  end

  def plan(meal)
    steps = {}

    meal.recipes.values.each do |recipe|
      t = 0
      t -= recipe.buffer

      recipe.steps.reverse.each do |step|
        start = step.parallel? ? t : t - step.time
        steps[start] ||= []
        steps[t] ||= []

        if available?(step.resources, start, t)
          claim!(step.resources, start, t)
          steps[start] << "[#{recipe.name}] #{step.to_s} " + (step.resources ? "[#{step.resources}]" : "")
          steps[t] << "[#{recipe.name}] #{step.stop_string}" if step.stop?
          t -= step.time unless step.parallel?
        else
          raise "Can't find resource for step: #{step.name} for recipe: #{recipe.name}"
        end
      end
    end

    steps
  end

  def to_s
    @resources.map(&:to_s).join("\n")
  end
end

class Resource
  attr_reader :name

  def initialize(name)
    @name = name
    @schedule = {}
  end

  def available?(start, stop)
    (start...stop).each do |t|
      return false if @schedule[t]
    end
    return true
  end

  def claim!(start, stop)
    (start..stop).each do |t|
      @schedule[t] = true
    end
  end

  def to_s
    "#{@name} \t #{self.busy? ? "USED" : "FREE"}"
  end

  def busy?
    false
  end
end

def main
  recipes = YAML.load(File.read("#{MEAL}.yml"))
  kitchen = Kitchen.new(YAML.load(File.read("#{KITCHEN}.yml"))['kitchen'])
  banner "kitchen"
  meal = Meal.new(recipes['meal'])

  kitchen.plan!(meal)
end

main
