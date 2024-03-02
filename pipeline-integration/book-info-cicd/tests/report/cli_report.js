// This script extracts all the results 

const fs = require('fs');

let rawReport = fs.readFileSync('report/output/cucumber_report.json');
let report = JSON.parse(rawReport);

let output = {
     passed: 0,
     failed: 0,
     skipped: 0,
     undefined: 0,
     scenarios: 0,
     steps: 0
}

report.forEach((scenario) => {
     scenario.elements.forEach((feature) => {
          output.scenarios += 1;
          feature.steps.forEach((step) => {
               output.steps += 1;
               if (step.result.status == 'undefined') {
                    output.undefined += 1;
               } else if (step.result.status == 'failed') {
                    output.failed += 1;
               } else if (step.result.status == 'skipped') {
                    output.skipped += 1;
               } else if (step.result.status == 'passed') {
                    output.passed += 1;
               } else {
                    console.log(`Unexpected status code: ${step.result.status}`);
               }
          })
     });
})

console.log(output);