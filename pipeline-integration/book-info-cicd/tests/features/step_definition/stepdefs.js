const assert = require('assert')

const { Given, When, Then, After, setDefaultTimeout } = require('@cucumber/cucumber');

const {By, until} = require("selenium-webdriver");

setDefaultTimeout(120 * 1000) // 120 seconds timeout for each step function

Given('I open bookinfo as a {string}', async function (userType) {
    await this.driver.get(process.env.BOOKINFO_URL);

    let element = await this.driver.findElement(By.linkText(userType));
    await element.click()
});

Given('I open bookinfo', async function () {
    await this.driver.get(process.env.BOOKINFO_URL);

    let element = await this.driver.findElement(By.className('text-center text-primary'));
    let value = await element.getAttribute('innerText');

    await assert.strictEqual(value, "The Comedy of Errors");
});

When('I login as {string} with password {string}', async function (username, password) {
    let btnLogin = await this.driver.findElement(By.className('btn btn-default navbar-btn navbar-right'));
    await btnLogin.click()
    
    await new Promise(resolve => setTimeout(resolve, 1000));

    await this.driver.findElement(By.name('username')).sendKeys(username);
    await this.driver.findElement(By.name('passwd')).sendKeys(password);

    
    let btnSubmitLogin = await this.driver.findElement(By.className('btn btn-primary'));
    await btnSubmitLogin.click();
});

Then('I should be logged in', async function () {
    let element = await this.driver.findElement(By.js(() => {
        return document.querySelectorAll('a[href^=logout]')[0];
    }));
    let value = await element.getAttribute('innerText')

    await assert.strictEqual(value, "sign out");
});

After(function () {
    return this.driver.quit();
});
