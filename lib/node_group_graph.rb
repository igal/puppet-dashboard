module NodeGroupGraph
  # Returns a hash of all the groups for this group/node, direct or inherited.
  # Each key is a group, and each value is the Set of parents for that group.
  def node_group_list
    return @node_group_list if @node_group_list
    all = {}
    self.walk(:node_groups,:loops => false) do |group,children|
      children.each do |child|
        all[child] ||= Set.new
        all[child] << group
      end
      group
    end
    @node_group_list = all
  end

  def node_group_graph
    @node_group_graph ||= self.walk(:node_groups,:loops => false) do |group,children|
      {group => children.inject({},&:merge)}
    end.values.first
  end

  def node_class_list
    return @node_class_list if @node_class_list
    all = {}
    self.walk(:node_groups,:loops => false) do |group,_|
      group.node_classes.each do |node_class|
        all[node_class] ||= Set.new
        all[node_class] << group
      end
      group
    end
    @node_class_list = all
  end

  # Collects all the parameters of the node, starting at the "most distant" groups
  # and working its ways up to the node itself. If there is a conflict between two
  # groups at the same level, the conflict is deferred to the next level. If the
  # conflict reaches the top without being resolved, a ParameterConflictError is
  # raised.
  def compiled_parameters(allow_conflicts=false)
    unless @compiled_parameters
      @compiled_parameters,@conflicts = self.walk(:node_groups,:loops => false) do |group,children|
        # Pick-up conflicts that our children had
        conflicts = children.map(&:last).inject(Set.new,&:merge)
        params = group.parameters.to_hash.map { |key,value|
          {key => [value,Set[group]]}
        }.inject({},&:merge)
        inherited = {}
        # Now collect our inherited params and their conflicts
        children.map(&:first).map {|h| [*h]}.flatten.each_slice(3) do |key,value,source|
          if inherited[key] && inherited[key].first != value
            conflicts.add(key)
            inherited[key].last << source.first
          else
            inherited[key] = [value,source]
          end
        end
        # Resolve all possible conflicts
        conflicts.each do |key|
          conflicts.delete(key) if params[key]
        end
        [params.reverse_merge(inherited), conflicts]
      end
      @conflicts.each { |key| errors.add(:parameters,key) }
    end
    raise ParameterConflictError unless allow_conflicts or @conflicts.empty?
    @compiled_parameters
  end

  def parameter_list
    compiled_parameters.map{|key,value_sources_pair| {key => value_sources_pair.first}}.inject({},&:merge)
  end

  # Options include
  #  - loops [true|false] : whether to allow loops. If set to false, will return nil when a node is
  #                         visited a second time on a single branch
  # NL: Possible options that might need to be added some day:
  #  - compact [true|false] : whether to flatten the returned list. This always happens now.
  #  - default : the value to return when a loop is found. This is currently always nil.
  #  - memo [true|false] : whether to memoize the results for a particular node. This doesn't happen now.
  def walk(branch_method,options={},&block)
    def do_dfs(branch_method,options,all,seen,&block)
      return nil if seen.include?(self) and options[:loops] == false
      all << self
      results = self.send(branch_method).map{|b| b.do_dfs(branch_method,options,all,seen+[self],&block)}.compact
      yield self,results
    end
    options.reverse_merge({:loops => false})
    return unless block
    seen = []
    all = []
    do_dfs(branch_method,options,all,seen,&block)
  end
end
