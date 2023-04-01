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

  const shutdown = async () => {
    await page.close();
    await context.close();
    await browser.close();
    process.exit(0);
  }

  const sendErrorMessage = (message) => {
    sendMessage(JSON.stringify(message))
    return shutdown();
  }

  const continueIfGoodResponse = async (response, url, callback) =>
    response.status() === 200
      ? callback()
      : sendErrorMessage({
          error: "bad_response",
          response_body: await response.body().then(body => body.toString()),
          status: response.status(),
          url,
        })

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

  const waitForResultsList = async () => {
    await page.waitForLoadState("load");
    if (await page.isVisible("#input-user-name")) { 
      await signIn();
    }
    return locators.resultsList.waitFor({ timeout })
      .then(() => sendMessage("ready_for_requests"))
      .catch((error) =>
        sendErrorMessage({
          error: error.message.startsWith("Timeout") ? "timeout" : "unknown",
          message: error.message
        }))

  }

  const connectToSite = async () => {
    const url = BASE_URL + "/catalog?view=list"
    const response = await page.goto(url);
    return continueIfGoodResponse(response, url, waitForResultsList)
  }

  const parseJSON = (json) => {
    try {
      return JSON.parse(json)
    } catch (error) {
      sendErrorMessage({error: "json_parse_error", message: error.message, input: json})
    }
  }

  const sendApiRequest = async (json) => {
    const { initial_cursor_mark, code, call_count } = parseJSON(json)
    if (typeof(call_count) !== "number") {
      throw new Error("expected call_count to be a number, got: " + json)
    }
    if (call_count > 1 && !initial_cursor_mark) {
      throw new Error("expected initial_cursor_mark after first request, got: " + json)
    }

    const url = BASE_URL + "/api/v2/search";

    const response = await page.request.get(url, {
      params: params({
        initialCursorMark: initial_cursor_mark,
        taxonCode: code
      })
    });

    const sendResponseMessage = async () => {
      const results = parseJSON((await response.body()).toString());
      sendMessage(JSON.stringify(results));
    }


    return continueIfGoodResponse(
      response,
      url,
      sendResponseMessage
    )
  }

  const handleInput = async (buffer) => {
    const message = buffer.toString()
    if (message === "connect") {
      return await connectToSite();
    }
    if (message === "shutdown") {
      return await shutdown();
    }
    await sendApiRequest(message);
  }

  process.stdin.addListener("data", handleInput)
})()