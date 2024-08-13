/*
const express = require('express');
const serve = require('express-static');
require('http-shutdown').extend();

const app = express();

app.use(serve(__dirname + '/dist/app'));

const server = app.listen(8080, function(){
  console.log("Server running");
}).withShutdown();

(async () => {
  try {
    import('./output-es/Test.Puppeteer/index.js').then(({ main }) => {
      main().then(serverDown);
    }).catch(err => {
      console.error("Failed to load PureScript output:", err);
    });
  } catch (error) {
    console.error('Error:', error);
  }
})();

function serverDown()
{
  console.log('Shutting down server')
  server.shutdown(function(err) {
    if (err) {
      return console.log('shutdown failed', err.message);
    }
    console.log('Everything is cleanly shutdown.');
  });

}
*/

///////////////////////

const http = require('http');
const express = require('express');
const serve = require('express-static');
const puppeteer = require('puppeteer');
require('http-shutdown').extend();

const app = express();

app.use(serve(__dirname + '/dist/app'));

const server = app.listen(8080, function(){
  console.log("Server running");
}).withShutdown();    

(async () => {
    try {
      console.log('Launching browser')
      const browser = await puppeteer.launch();
      const page = await browser.newPage();
      await page.goto('http://127.0.0.1:8080');
      const content = await page.content();
      console.log(content);
      
      await checkForFigure(page, "fig-4");
      await checkForFigure(page, "fig-1");
      await checkForFigure(page, "fig-conv-2");

      await browser.close();
      console.log("Browser closed");
      
    } catch (error) {
      console.error('Error:', error);
    }
    console.log('Shutting down server')
    await server.shutdown(function(err) {
      if (err) {
        return console.log('shutdown failed', err.message);
      }
      console.log('Everything is cleanly shutdown.');
      
    });
  })();

  async function checkForFigure(page, id) {
    const selector = `div#${id}`;
    console.log(`Waiting for ${selector}`);
    await page.waitForSelector(selector, { timeout: 60000 });
    console.log(`Found ${selector}`); 
  }
