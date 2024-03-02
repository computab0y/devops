const { setWorldConstructor, World } = require('@cucumber/cucumber')
const chrome = require('selenium-webdriver/chrome');
const seleniumWebdriver = require('selenium-webdriver')
require('chromedriver');

class CustomWorld extends World {
    driver = new seleniumWebdriver.Builder()
          .forBrowser('chrome')
          .setChromeOptions(new chrome.Options().addArguments('--headless')
                                                .addArguments("--disable-extensions")
                                                .addArguments("--disable-gpu")
                                                .addArguments("--disable-dev-shm-usage")
                                                .addArguments("--no-sandbox")
                                                )
          .build();
    
    constructor(options) {
        super(options)
    }
  
    // Returns a promise that resolves to the element
    async waitForElement(locator) {
        const condition = seleniumWebdriver.until.elementLocated(locator)
        return await this.driver.wait(condition)
    }
}

setWorldConstructor(CustomWorld);