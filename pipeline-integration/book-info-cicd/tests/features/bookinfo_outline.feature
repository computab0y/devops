Feature: Can others log into BookInfo

  Scenario Outline: Access book info as different users
    Given I open bookinfo
    When I login as "<username>" with password "<password>"
    Then I should be logged in

  Examples:
    | userType    | username | password   |
    | Normal user | john.doe | pa$$w0rd   |
    | Test user   | test123  | hello      |
    | Normal user | admin    | cI9pFzr4sW |