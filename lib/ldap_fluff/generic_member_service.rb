# frozen_string_literal: true

# @abstract
class LdapFluff::GenericMemberService
  # @return [Net::LDAP]
  attr_accessor :ldap

  # @!attribute [r] config
  #   @return [LdapFluff::Config]
  # @!attribute [r] search_filter
  #   @return [Net::LDAP::Filter]
  attr_reader :config, :search_filter

  # @param [Net::LDAP] ldap
  # @param [LdapFluff::Config] config
  def initialize(ldap, config)
    @ldap   = ldap
    @config = config

    @search_filter    = try_create_filter(config.search_filter)
    @login_attributes = [config.attr_login, 'uid', 'cn']
  end

  # @param [String] filter
  # @return [Net::LDAP::Filter]
  def try_create_filter(filter, kind = :Search)
    !filter || filter.empty? ? nil : Net::LDAP::Filter.construct(filter)
  rescue Net::LDAP::Error => e
    warn "#{kind} filter unavailable - #{e}"
    nil
  end

  # @param [String] uid
  # @return [Array<Net::LDAP::Entry>, Net::LDAP::Entry]
  # @raise [UIDNotFoundException]
  def find_user(uid, only = nil)
    # @type [Array<Net::LDAP::Entry>]
    user = ldap.search(filter: name_filter(uid))
    raise self.class::UIDNotFoundException if !user || user.empty?

    return_one_or_all(user, only)
  end

  # @param [String] dn
  # @return [Array<Net::LDAP::Entry>, Net::LDAP::Entry]
  # @raise [UIDNotFoundException]
  def find_by_dn(dn, only = nil)
    # @type [String] entry
    entry, base = dn.split(/(?<!\\),/, 2)
    entry_attr, entry_value = entry.split('=', 2)
    entry_value = entry_value.gsub('\,', ',')

    # @type [Array<Net::LDAP::Entry>]
    user = ldap.search(filter: name_filter(entry_value, entry_attr), base: base)
    raise self.class::UIDNotFoundException if !user || user.empty?

    return_one_or_all(user, only)
  end

  # @param [String] gid
  # @return [Array<Net::LDAP::Entry>, Net::LDAP::Entry]
  # @raise [UIDNotFoundException]
  def find_group(gid, only = nil)
    # @type [Array<Net::LDAP::Entry>]
    group = ldap.search(filter: group_filter(gid), base: config.group_base)
    raise self.class::GIDNotFoundException if !group || group.empty?

    return_one_or_all(group, only)
  end

  # @param [String] uid
  # @return [Array<String>]
  # @abstract
  def find_user_groups(uid)
    raise NotImplementedError, uid.inspect
  end

  # @param [String] uid
  # @return [Net::LDAP::Filter]
  def name_filter(uid, attr = config.attr_login)
    filter = Net::LDAP::Filter.eq(attr, uid)
    search_filter ? (filter & search_filter) : filter
  end

  # @param [String] gid
  # @return [Net::LDAP::Filter]
  def group_filter(gid, attr = 'cn')
    Net::LDAP::Filter.eq(attr, gid)
  end

  # @param [String] name
  # @return [Net::LDAP::Filter]
  def class_filter(name)
    Net::LDAP::Filter.eq('objectClass', name)
  end

  # extract the group names from the LDAP style response,
  # @param [Array<String>] grouplist
  # @return [Array<String>] will be something like CN=bros,OU=bropeeps,DC=jomara,DC=redhat,DC=com
  def get_groups(grouplist, attr = 'cn')
    grouplist.map { |g| g.sub(/.*?\b#{attr}=([^,]*).*/i, '\1') }
  end

  # @param [Array<String>] netgroup_triples
  # @return [Array<String>]
  def get_netgroup_users(netgroup_triples)
    netgroup_triples ? netgroup_triples.map { |m| m.split(',')[1] } : []
  end

  # @param [Array<String>] userlist
  # @return [Array<String>]
  def get_logins(userlist)
    userlist.map { |g| g.sub(/.*?\b(?:#{@login_attributes.join('|')})=([^,]*).*/i, '\1') }
  end

  # @param [Net::LDAP::Entry] entry
  # @return [String]
  def get_login_from_entry(entry)
    @login_attributes.each do |attribute|
      return entry.send(attribute) if entry.respond_to? attribute
    end

    nil
  end

  protected

  # @param [Array] arr
  def return_one_or_all(arr, only = nil)
    return arr if only.nil?

    only ? arr.first : arr.last
  end
end
