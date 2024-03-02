const reporter = require('cucumber-html-reporter');

let options = {
    theme: 'bootstrap',
    jsonFile: 'report/output/cucumber_report.json',
    output: 'report/output/cucumber_report.html',
    reportSuiteAsScenarios: true,
    scenarioTimestamp: true,
    launchReport: false
};

reporter.generate(options);