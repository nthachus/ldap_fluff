# frozen_string_literal: true

require_relative 'ldap_test_helper'

class TestIPAMemberService < MiniTest::Test
  include LdapTestHelper

  def setup
    super
    # noinspection RubyYardParamTypeMatch
    @ipams = LdapFluff::FreeIPA::MemberService.new(ldap, config)
  end

  def basic_user
    ldap.expect(:search, ipa_user_payload, [filter: ipa_name_filter('john')])
  end

  def basic_group
    ldap.expect(:search, ipa_group_payload, [filter: ipa_group_filter('broze'), base: config.group_base])
  end

  def test_find_user
    basic_user
    @ipams.ldap = ldap

    assert_equal(%w[group bros], @ipams.find_user_groups('john'))
  end

  def test_missing_user
    ldap.expect(:search, nil, [filter: ipa_name_filter('john')])
    @ipams.ldap = ldap

    assert_raises(LdapFluff::FreeIPA::MemberService::UIDNotFoundException) do
      @ipams.find_user_groups('john').data
    end
  end

  def test_no_groups
    entry = Net::LDAP::Entry.new
    entry[:memberof] = []
    ldap.expect(:search, [Net::LDAP::Entry.new, entry], [filter: ipa_name_filter('john')])
    @ipams.ldap = ldap

    assert_equal([], @ipams.find_user_groups('john'))
  end

  def test_find_good_user
    basic_user
    @ipams.ldap = ldap

    assert_equal(ipa_user_payload, @ipams.find_user('john'))
  end

  def test_find_missing_user
    ldap.expect(:search, nil, [filter: ipa_name_filter('john')])
    @ipams.ldap = ldap

    assert_raises(LdapFluff::FreeIPA::MemberService::UIDNotFoundException) do
      @ipams.find_user('john')
    end
  end

  def test_find_good_group
    basic_group
    @ipams.ldap = ldap

    assert_equal(ipa_group_payload, @ipams.find_group('broze'))
  end

  def test_find_missing_group
    ldap.expect(:search, nil, [filter: ipa_group_filter('broze'), base: config.group_base])
    @ipams.ldap = ldap

    assert_raises(LdapFluff::FreeIPA::MemberService::GIDNotFoundException) do
      @ipams.find_group('broze')
    end
  end

  def test_ipa_unique_groups
    user = Net::LDAP::Entry.new.tap { |e| e[:memberof] = %w[cn=group,dc ipauniqueid=bros] }
    ldap.expect(:search, [nil, user], [filter: ipa_name_filter('john')])

    entry = Net::LDAP::Entry.new.tap { |e| e[:cn] = 'broze' }
    ldap.expect(:search, [entry], [base: user[:memberof].last])
    @ipams.ldap = ldap

    assert_equal %w[group broze], @ipams.find_user_groups('john')
  end
end
