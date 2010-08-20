class Node < ActiveRecord::Base
  def self.per_page; 20 end # Pagination

  include NodeGroupGraph

  validates_presence_of :name
  validates_uniqueness_of :name

  has_many :node_class_memberships, :dependent => :destroy
  has_many :node_classes, :through => :node_class_memberships
  has_many :node_group_memberships, :dependent => :destroy
  has_many :node_groups, :through => :node_group_memberships

  has_many :reports, :dependent => :destroy
  belongs_to :last_report, :class_name => 'Report'

  named_scope :with_last_report, :include => :last_report
  named_scope :by_report_date, :order => 'reported_at DESC'

  named_scope :search, lambda{|q| q.blank? ? {} : {:conditions => ['name LIKE ?', "%#{q}%"]} }

  # ordering scopes for has_scope
  named_scope :by_latest_report, proc { |order| 
    direction = {1 => 'ASC', 0 => 'DESC'}[order]
    direction ? {:order => "reported_at #{direction}"} : {}
  }

  has_parameters

  fires :created, :on => :create
  fires :updated, :on => :update
  fires :removed, :on => :destroy

  # RH:TODO: Denormalize last report status into nodes table.

  # Return nodes based on their currentness and successfulness.
  #
  # The terms are:
  # * currentness: +true+ uses the latest report (current) and +false+ uses any report.
  # * successfulness: +true+ means a successful report, +false+ a failing report.
  #
  # Thus:
  # * current and successful: Return only nodes that are currently successful.
  # * current and failing: Return only nodes that are currently failing.
  # * non-current and successful: Return any nodes that ever had a successful report.
  # * non-current and failing: Return any nodes that ever had a failing report.
  named_scope :by_currentness_and_successfulness, lambda {|currentness, successfulness|
    if currentness
      { :conditions => ['nodes.success = ?', successfulness] }
    else
      {
        :conditions => ['reports.success = ?', successfulness],
        :joins => :reports,
        :group => 'nodes.id',
      }
    end
  }

  # Return nodes that have never reported.
  named_scope :unreported, :conditions => {:reported_at => nil}

  # Seconds in the past since a node's last report for a node to be considered no longer reporting.
  # Defaults to twice the default puppet run period to prevent timing errors.
  NO_LONGER_REPORTING_CUTOFF = 1.hour

  # Return nodes that haven't reported recently.
  named_scope :no_longer_reporting, :conditions => ['reported_at < ?', NO_LONGER_REPORTING_CUTOFF.ago]

  def self.count_by_currentness_and_successfulness(currentness, successfulness)
    # FIXME The #length call is inefficient, but how do I make #count work since it lacks support for :having?
    # self.by_currentness_and_successfulness(currentness, successfulness).count(:id, :distinct => :id)
    self.by_currentness_and_successfulness(currentness, successfulness).length
  end

  def self.label_for_currentness_and_successfulness(currentness, successfulness)
    return "#{currentness ? 'Currently' : 'Ever'} #{successfulness ? (currentness ? 'successful' : 'succeeded') : (currentness ? 'failing' : 'failed')}"
  end

  def self.count_unreported
    unreported.count
  end

  def self.count_no_longer_reporting
    no_longer_reporting.count
  end

  def to_param
    name.to_s
  end

  def available_node_classes
    @available_node_classes ||= NodeClass.all(:order => :name) - node_classes - inherited_classes
  end

  def available_node_groups
    @available_node_groups ||= NodeGroup.all(:order => :name) - node_groups
  end

  def inherited_classes
    (node_group_list.keys - [self]).map(&:node_classes).flatten.uniq
  end

  def all_classes
    node_classes | inherited_classes
  end

  def configuration
    { 'name' => name, 'classes' => all_classes.collect(&:name), 'parameters' => parameter_list }
  end

  def to_yaml(opts={})
    configuration.to_yaml(opts)
  end

  def timeline_events
    TimelineEvent.for_node(self)
  end

  # Placeholder attributes
  
  def environment
    'production'
  end

  def status_class
    return 'no reports' unless last_report
    last_report.status
  end

  attr_accessor :node_class_names
  after_save :assign_node_classes
  def assign_node_classes
    return true unless @node_class_names
    self.node_classes = (@node_class_names || []).reject(&:blank?).map{|name| NodeClass.find_by_name(name)}
  end

  attr_accessor :node_group_names
  after_save :assign_node_groups
  def assign_node_groups
    return true unless @node_group_names
    self.node_groups = (@node_group_names || []).reject(&:blank?).map{|name| NodeGroup.find_by_name(name)}
  end

  def find_last_report
    return Report.find_last_for(self)
  end
end
