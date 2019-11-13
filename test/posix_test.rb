# frozen_string_literal: true

require 'ldap_test_helper'

class TestPosix < MiniTest::Test
  include LdapTestHelper

  def setup
    super
    @posix = LdapFluff::Posix.new(@config)
  end

  def service_bind
    @ldap.expect(:auth, nil, %w[service pass])
    super
  end

  def test_groups
    service_bind
    basic_user
    assert_equal(@posix.groups_for_uid('john'), %w[bros])
  end

  def test_missing_user
    md = MiniTest::Mock.new
    md.expect(:find_user_groups, [], %w[john])
    @posix.member_service = md
    assert_equal([], @posix.groups_for_uid('john'))
  end

  def test_isnt_in_groups
    service_bind
    basic_user
    assert_equal(@posix.is_in_groups('john', %w[broskies], true), false)
  end

  def test_is_in_groups
    service_bind
    basic_user
    assert_equal(@posix.is_in_groups('john', %w[bros], true), true)
  end

  def test_is_in_no_groups
    service_bind
    basic_user
    assert_equal(@posix.is_in_groups('john', [], true), true)
  end

  def test_good_bind
    # looks up the uid's full DN via the service account
    @md = MiniTest::Mock.new
    user_result = MiniTest::Mock.new
    user_result.expect(:dn, 'uid=internet,dn=example')
    @md.expect(:find_user, [user_result], %w[internet])
    @posix.member_service = @md
    service_bind
    @ldap.expect(:auth, nil, %w[uid=internet,dn=example password])
    @ldap.expect(:bind, true)
    @posix.ldap = @ldap
    assert_equal(@posix.bind?('internet', 'password'), true)
  end

  def test_good_bind_with_dn
    # no expectation on the service account
    @ldap.expect(:auth, nil, %w[uid=internet,dn=example password])
    @ldap.expect(:bind, true)
    @posix.ldap = @ldap
    assert_equal(@posix.bind?('uid=internet,dn=example', 'password'), true)
  end

  def test_bad_bind
    @ldap.expect(:auth, nil, %w[uid=internet,dn=example password])
    @ldap.expect(:bind, false)
    @posix.ldap = @ldap
    assert_equal(@posix.bind?('uid=internet,dn=example', 'password'), false)
  end

  def test_user_exists
    service_bind
    md = MiniTest::Mock.new
    md.expect(:find_user, 'notnilluser', %w[john])
    @posix.member_service = md
    assert(@posix.user_exists?('john'))
  end

  def test_missing_user
    service_bind
    md = MiniTest::Mock.new
    md.expect(:find_user, nil) do |uid|
      raise LdapFluff::Posix::MemberService::UIDNotFoundException if uid == 'john'
    end
    @posix.member_service = md
    refute(@posix.user_exists?('john'))
  end

  def test_group_exists
    service_bind
    md = MiniTest::Mock.new
    md.expect(:find_group, 'notnillgroup', %w[broskies])
    @posix.member_service = md
    assert(@posix.group_exists?('broskies'))
  end

  def test_missing_group
    service_bind
    md = MiniTest::Mock.new
    md.expect(:find_group, nil) do |gid|
      raise LdapFluff::Posix::MemberService::GIDNotFoundException if gid == 'broskies'
    end
    @posix.member_service = md
    refute(@posix.group_exists?('broskies'))
  end

  def test_find_users_in_nested_groups
    service_bind
    group = Net::LDAP::Entry.new('CN=foremaners,DC=example,DC=com')
    group[:memberuid] = ['katellers']
    nested_group = Net::LDAP::Entry.new('CN=katellers,CN=foremaners,DC=example,DC=com')
    nested_group[:memberuid] = ['testuser']

    @ldap.expect(:search, [nested_group], [base: group.dn, filter: groups_filter])
    @posix.ldap = @ldap

    md = MiniTest::Mock.new
    2.times { md.expect(:find_group, [group], ['foremaners']) }
    @posix.member_service = md

    assert_equal @posix.users_for_gid('foremaners'), ['testuser']

    md.verify
    @ldap.verify
  end

  private

  def groups_filter
    Net::LDAP::Filter.eq('objectClass', 'posixGroup') |
      Net::LDAP::Filter.eq('objectClass', 'organizationalunit') |
      Net::LDAP::Filter.eq('objectClass', 'groupOfUniqueNames') |
      Net::LDAP::Filter.eq('objectClass', 'groupOfNames')
  end
end
