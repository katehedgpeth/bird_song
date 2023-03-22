const File = require("fs");
const {chromium} = require("playwright");
const STORAGE_STATE = require("./playwright_auth.json");
const [, , BASE_URL, STORAGE_STATE_PATH] = process.argv;
const USERNAME = process.env.EBIRD_USERNAME;
const PASSWORD = process.env.EBIRD_PASSWORD;

if (!BASE_URL || !STORAGE_STATE_PATH) {
  console.log({argv: process.argv, error: "Received less arguments than expected"})
  throw new Error()
}

const timeout = 3_000;

// if (!USERNAME) throw new Error("missing env var: EBIRD_USERNAME")
// if (!PASSWORD) throw new Error("missing env var: EBIRD_PASSWORD")



const sendMessage = (data) => {
  console.log("message=" + data)
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ storageState: STORAGE_STATE });
  const page = await context.newPage();
  const params = ({ initialCursorMark, taxonCode }) => (
    {
      initialCursorMark,
      mediaType: "audio",
      sort: "rating_rank_desc",
      taxonCode,
      view: "list",
    }
  );

  const resultsList = page.locator(".ResultsList");
  const locators = {
    moreButton : page.locator(".pagination > .Button"),
    result: resultsList.locator("li"),
    resultsList,
  }

  const signIn = async () => {
    await page.type("#input-user-name", USERNAME);
    await page.type("#input-password", PASSWORD);
    return page.click("#form-submit");
  }

  const connectToSite = async () => {
    await page.goto(BASE_URL + "/catalog?view=list");
    // await page.screenshot({ path: "./screenshot.png" })
    await page.waitForLoadState("load");
    if (await page.isVisible("#input-user-name")) { 
      await signIn();
    }
    await locators.resultsList.waitFor({ timeout });
    sendMessage("ready_for_requests")

  }

  // const clickAndWaitForResults = async (clickNum) => {
  //   await locators.moreButton.scrollIntoViewIfNeeded({ timeout: 0 });
  //   await locators.moreButton.click({ timeout: 0 });
  //   return waitForResults(clickNum);
  // }

  // const waitForResults = async (clickNum) => {
  //   const count = await locators.result.count();
  //   if (count < clickNum * 30) {
  //     await page.waitForTimeout(500);
  //     return waitForResults(clickNum);
  //   }
  //   await page.screenshot(`./screenshot_${clickNum}.png`);
  // }

  const sendApiRequest = async (json) => {

    const { initial_cursor_mark, code, call_count } = JSON.parse(json)
    if (typeof(call_count) !== "number") {
      throw new Error("expected call_count to be a number, got: " + json)
    }
    if (call_count > 1 && !initial_cursor_mark) {
      throw new Error("expected initial_cursor_mark after first request, got: " + json)
    }

    const response = await page.request.get(
      BASE_URL + "/api/v2/search",
      { params: params({
        initialCursorMark: initial_cursor_mark,
        taxonCode: code
      }) }
    );
    const results = JSON.parse((await response.body()).toString());
    sendMessage(JSON.stringify(results))
  }

  const handleInput = async (buffer) => {
    const message = buffer.toString()
    if (message === "connect") {
      return connectToSite()
    }
    return sendApiRequest(message)
  }

  process.stdin.addListener("data", handleInput)


  // const MAX_PAGES = 3;

  // const getPages = async (pageCount, acc) => {
  //   // await page.waitForTimeout(REQUEST_THROTTLE);
  //   return getPages(pageCount + 1, acc.concat(results));
  // }

  // const results = await getPages(1, []);
  // await locators.moreButton.scrollIntoViewIfNeeded({ timeout: 100 });
  // await clickAndWaitForResults(1);
  // await clickAndWaitForResults(2);
  // await clickAndWaitForResults(3);

  // const idPromises = [];
  // const results = await locators.result.all();

  // results.forEach(recording => {
  //   idPromises.push(recording.locator("a", {hasText: /ML\d+/}).first().textContent());
  // });

  // const ids = await Promise.all(idPromises);

  const shutdown = async () => {
    await context.close();
    await browser.close();
    console.log(JSON.stringify(results))
  }
  // console.log(JSON.stringify({ ids }));
})()