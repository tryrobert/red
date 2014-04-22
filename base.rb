module Report::Productivity
  class Base
    def initialize(access_scope, range)
      @access_scope = access_scope
      @range = adaption_range(range)
    end

    def select_projects(project_ids)
      @project_ids = project_ids
    end

    def select_employees(employee_ids)
      @employee_ids = employee_ids
    end

    def employee_condition(query)
      application_summaries = Arel::Table.new(:application_summaries)
      query.where(application_summaries[:user_id].in(@employee_ids))
    end

    def project_condition(query)
      application_summaries = Arel::Table.new(:application_summaries)
      query.where(application_summaries[:project_id].in(@project_ids))
    end

    def application_summary_condition(query)
      return if @range.blank?

      application_summaries = Arel::Table.new(:application_summaries)
      offset_start = application_summaries[:offset_start]
      offset_end = application_summaries[:offset_end]
      duration = application_summaries[:duration]
      activity_day = application_summaries[:activity_day]


      if transition_days.blank?
        query.where(activity_day.in(@range))
        query.where(offset_start.eq(offset(@range.first)))
        query.where(offset_end.eq(offset(@range.last)))
        query.where(duration.gt(0))
      else
        condition = nil
        date_intervals.each do |x|
          if condition.nil?
            condition = activity_day.in(x[:date_range])
            .and(offset_start.eq(x[:offset_start]))
            .and(offset_end.eq(x[:offset_end]))
          else
            condition = condition.or(activity_day.in(x[:date_range])
              .and(offset_start.eq(x[:offset_start]))
              .and(offset_end.eq(x[:offset_end]))
            )
          end
        end
        query.where(condition)
      end
    end

    protected

    def uniq_ids(activity_summary, key)
      activity_summary.map do |activity|
        activity[key]
      end.uniq
    end

    def access_scope
      @access_scope
    end

    def range
      @range
    end

    def transition_days
      @transitions_days ||= dst_started_and_ended_days
    end

    private

    def dst_started_and_ended_days
      from_date = to_time_in_time_zone(@range.first, tz).beginning_of_day
      to_date = (to_time_in_time_zone(@range.last, tz)).end_of_day
      tz.transitions_up_to(to_date, from_date).map { |date| date.time.to_date }
    end

    def tz
      @tz ||= TZInfo::Timezone.get(@access_scope.user.time_zone)
    end

    def to_time_in_time_zone(date, zone)
      date.to_time.in_time_zone(zone)
    end

    def offset(date)
      to_time_in_time_zone(date, tz).utc_offset
    end

    def adaption_range(range)
      from = range.begin.to_date
      to = range.end.to_date

      from..to
    end

    def date_intervals
      result = []
      start_day = @range.first
      end_day = @range.last

      transition_days.each do |transition_day|
        if start_day != transition_day
          result << {
            date_range: start_day..(transition_day - 1.day),
            offset_start: offset(start_day),
            offset_end: offset(start_day)
          }
        end

        result << {
          date_range: transition_day..transition_day,
          offset_start: offset(transition_day),
          offset_end: offset(transition_day + 1.day)
        }

        start_day = transition_day + 1.day
      end

      if start_day <= end_day
        result << {
          date_range: start_day..(end_day),
          offset_start: offset(start_day),
          offset_end: offset(start_day)
        }
      end

      result
    end
  end
end
