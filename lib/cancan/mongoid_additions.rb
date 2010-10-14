module CanCan

  module Ability
    alias_method :query_without_mongoid_support, :query
    def query(action, subject)
      if Object.const_defined?(:Mongoid) && subject <= CanCan::MongoidAdditions
        query_with_mongoid_support(action, subject)
      else
        query_without_mongoid_support(action, subject)
      end
    end
    
    def query_with_mongoid_support(action, subject)
      MongoidQuery.new(subject, relevant_can_definitions_for_query(action, subject))
    end
  end
  
  class MongoidQuery
    def initialize(sanitizer, can_definitions)
      @sanitizer = sanitizer
      @can_definitions = can_definitions
    end    
    
    def conditions
      @can_definitions.first.try(:tableized_conditions)
    end
  end

  # customize to handle Mongoid queries in ability definitions conditions
  class CanDefinition
    def matches_conditions_hash?(subject, conditions = @conditions)          
      if subject.class.include?(Mongoid::Document)        # Mongoid Criteria are simpler to check than normal conditions hashes
        if conditions.empty?  # When no conditions are given, true should be returned.
                              # The default CanCan behavior relies on the fact that conditions.all? will return true when conditions is empty
                              # The way ruby handles all? for empty hashes can be unexpected:
                              #   {}.all?{|a| a == 5} 
                              #   => true
                              #   {}.all?{|a| a != 5} 
                              #   => true
          true
        else
          subject.class.where(conditions).include?(subject)  # just use Mongoid's where function
        end
      else 
        conditions.all? do |name, value|
          attribute = subject.send(name)
          if value.kind_of?(Hash)
            if attribute.kind_of? Array
              attribute.any? { |element| matches_conditions_hash? element, value }
            else
              matches_conditions_hash? attribute, value
            end
          elsif value.kind_of?(Array) || value.kind_of?(Range)
            value.include? attribute
          else
            attribute == value
          end
        end
      end
    end
  end



  module MongoidAdditions
    module ClassMethods
      # Returns a scope which fetches only the records that the passed ability
      # can perform a given action on. The action defaults to :read. This
      # is usually called from a controller and passed the +current_ability+.
      #
      #   @articles = Article.accessible_by(current_ability)
      # 
      # Here only the articles which the user is able to read will be returned.
      # If the user does not have permission to read any articles then an empty
      # result is returned. Since this is a scope it can be combined with any
      # other scopes or pagination.
      # 
      # An alternative action can optionally be passed as a second argument.
      # 
      #   @articles = Article.accessible_by(current_ability, :update)
      # 
      # Here only the articles which the user can update are returned. This
      # internally uses Ability#conditions method, see that for more information.
      def accessible_by(ability, action = :read)
        query = ability.query(action, self)        
        if query.conditions.blank?
          # this query is sure to return no results
          # we need this so there is a Mongoid::Criteria object to return, since an empty array would cause problems
          where({:_id => {'$exists' => false, '$type' => 7}})  # type 7 is an ObjectID (default for _id)
        else   
          where(query.conditions)
        end
      end
    end
    
    def self.included(base)
      base.extend ClassMethods
    end
  end
end

# Info on monkeypatching Mongoid : 
# http://log.mazniak.org/post/719062325/monkey-patching-activesupport-concern-and-you#footer
if defined? Mongoid
  module Mongoid
    module Components
      old_block = @_included_block
      @_included_block = Proc.new do 
        class_eval(&old_block) if old_block
        include CanCan::MongoidAdditions
      end
    end
  end  
end