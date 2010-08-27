
class DomainLogGroup < DomainModel
  has_many :domain_log_stats, :dependent => :delete_all

  named_scope :for_target, lambda { |type, id| {:conditions => {:target_type => type, :target_id => id}} }
  named_scope :with_type, lambda { |type| {:conditions => {:stat_type => type}} }
  named_scope :started_at, lambda { |time| {:conditions => {:started_at => time}} }
  named_scope :with_duration, lambda { |duration| {:conditions => {:duration => duration.to_i}} }

  def expired?
    self.expires_at && self.expires_at < Time.now
  end

  def self.stats(target, from, duration, intervals, opts={})
    groups = []
    (1..intervals).each do |i|
      group = self.find_group(target, from, duration, opts)
      if group
        groups << group
      else
        scope = yield from, duration
        groups << self.create_group(target, from, duration, scope, opts)
      end
      from += duration
    end
    groups
  end

  def self.find_group(target, started_at, duration, opts={})
    target_type = target.is_a?(String) ? target : target.class.to_s
    target_id = target.is_a?(String) ? nil : target.id

    group = DomainLogGroup.started_at(started_at).with_duration(duration).for_target(target_type, nil).with_type(opts[:type]).first

    if group && group.expired?
      if target_id.nil?
        group.destroy
        return nil
      end
    end

    if group.nil? && target_id
      group = DomainLogGroup.started_at(started_at).with_duration(duration).for_target(target_type, target_id).with_type(opts[:type]).first
      if group && group.expired?
        group.destroy
        return nil
      end
    end

    group.target_id = target_id if group && target_id
    group
  end

  def self.create_group(target, started_at, duration, scope, opts={})
    target_type = target.is_a?(String) ? target : target.class.to_s
    target_id = target.is_a?(String) ? nil : target.id

    results = scope.find :all

    attributes = {
      :target_type => target_type,
      :target_id => target_id,
      :stat_type => opts[:type],
      :started_at => started_at,
      :duration => duration.to_i
    }

    attributes[:expires_at] = 5.minutes.since if (started_at + duration) > Time.now
    group = DomainLogGroup.create attributes

    results.each do |result|
      group.domain_log_stats.create result.attributes.slice('target_id', 'visits', 'hits', 'leads', 'conversions', 'stat1', 'stat2')
    end

    group
  end

  def target_stats(target_id=nil)
    target_id ||= self.target_id
    self.domain_log_stats.find(:all, :conditions => {:target_id => target_id})
  end
end
