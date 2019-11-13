# frozen_string_literal: true

class LdapFluff::GenericMemberService
  # @return [Net::LDAP]
  attr_accessor :ldap

  # @param [Net::LDAP] ldap
  # @param [Config] config
  def initialize(ldap, config)
    @ldap       = ldap
    @base       = config.base_dn
    @group_base = (config.group_base.empty? ? config.base_dn : config.group_base)

    @search_filter = nil
    begin
      @search_filter = Net::LDAP::Filter.construct(config.search_filter) unless
        !config.search_filter || config.search_filter.empty?
    rescue Net::LDAP::LdapError => e
      puts "Search filter unavailable - #{e}"
    end
  end

  # @param [String] uid
  # @return [Array, Net::LDAP::Entry]
  # @raise [UIDNotFoundException]
  def find_user(uid)
    user = @ldap.search(filter: name_filter(uid))
    raise self.class::UIDNotFoundException if (user.nil? || user.empty?)

    user
  end

  # @param [String] dn
  # @return [Array, Net::LDAP::Entry]
  # @raise [UIDNotFoundException]
  def find_by_dn(dn)
    # @type [String] entry
    entry, base = dn.split(/(?<!\\),/, 2)
    entry_attr, entry_value = entry.split('=', 2)
    entry_value = entry_value.gsub('\,', ',')

    user = @ldap.search(filter: name_filter(entry_value, entry_attr), base: base)
    raise self.class::UIDNotFoundException if !user || user.empty?

    user
  end

  def find_group(gid)
    group = @ldap.search(filter: group_filter(gid), base: @group_base)
    raise self.class::GIDNotFoundException if !group || group.empty?

    group
  end

  def name_filter(uid, attr = @attr_login)
    filter = Net::LDAP::Filter.eq(attr, uid)

    if @search_filter.nil?
      filter
    else
      filter & @search_filter
    end
  end

  def group_filter(gid)
    Net::LDAP::Filter.eq('cn', gid)
  end

  # extract the group names from the LDAP style response,
  # return string will be something like
  # CN=bros,OU=bropeeps,DC=jomara,DC=redhat,DC=com
  def get_groups(grouplist)
    grouplist.map { |g| g.downcase.sub(/.*?cn=(.*?),.*/, '\1') }
  end

  def get_netgroup_users(netgroup_triples)
    return [] unless netgroup_triples

    netgroup_triples.map { |m| m.split(',')[1] }
  end

  def get_logins(userlist)
    userlist.map(&:downcase!)
    [@attr_login, 'uid', 'cn'].map do |attribute|
      logins = userlist.map { |g| g.sub(/.*?#{attribute}=(.*?),.*/, '\1') }
      if logins == userlist
        nil
      else
        logins
      end
    end.uniq.compact.flatten
  end

  def get_login_from_entry(entry)
    [@attr_login, 'uid', 'cn'].each do |attribute|
      return entry.send(attribute) if entry.respond_to? attribute
    end
    nil
  end
end
