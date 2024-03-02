// Assumes OS has chrome-browser installed at the stable version  96

> export BOOKINFO_URL=YOUR_BOOK_INFO_URL

> npm install

> npm test


TODO: 
 - Cucumber Test Reporting / Clean output in machine useable format

 - Create an event listener and trigger to be hit from Argo CD 

 - Create a post deployment pipeline that runs cucumber
    - Triggered by Argo Deployment / Sync event
    - Initally use an image for node
    - (stretch goal) Preferebly use an image with all the required node_modules depenencies (or the binary dependencies being pulled from JFrog?)
