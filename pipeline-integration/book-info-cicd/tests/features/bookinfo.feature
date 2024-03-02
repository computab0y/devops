Feature: Can I log into BookInfo

  Scenario: Access sample book info as a normal user
    Given I open bookinfo 
    When I login as "bilal.tariq" with password "helloworld"
    Then I should be logged in

  Scenario: Access sample book info as a test user
    Given I open bookinfo
    When I login as "bilal.tariq" with password "helloworld"
    Then I should be logged in