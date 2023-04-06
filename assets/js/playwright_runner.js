const { chromium } = require("playwright");
const [, , BASE_URL, TIMEOUT] = process.argv;
const USERNAME = process.env.EBIRD_USERNAME;
const PASSWORD = process.env.EBIRD_PASSWORD;
const TAKE_SCREENSHOTS = process.env.PLAYWRIGHT_TAKE_SCREENSHOTS

if (!BASE_URL || !TIMEOUT) {
  console.log("message=" + JSON.stringify({argv: process.argv, error: "arguments"}))
  throw new Error("received less arguments than expected")
}

const timeout = parseInt(TIMEOUT, 10);

const sendMessage = (data) => {
  console.log("message=" + data)
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const takeScreenshot = (fileName) =>
    TAKE_SCREENSHOTS && page.screenshot({path: `./screenshots/${fileName}_${Date.now()}.png`});

  const shutdown = async () => {
    await page.close();
    await context.close();
    await browser.close();
    process.exit(0);
  }

  const sendErrorMessage = async (message) => {
    await takeScreenshot("on_send_error_message")
    return sendMessage(JSON.stringify(message));
  }

  const catchTimeoutError = (error) =>
    sendErrorMessage({
      error: error.message.includes("Timeout") ? "timeout" : "unknown",
      message: error.message
    })

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
    await takeScreenshot("before_click_sign_in")
    await page.locator("a.Header-link").getByText("Sign in").click({ timeout }).catch(catchTimeoutError);
    await takeScreenshot("after_click_sign_in")
    await page.type("#input-user-name", USERNAME, { timeout }).catch(catchTimeoutError);
    await page.type("#input-password", PASSWORD, { timeout }).catch(catchTimeoutError);
    await page.click("#form-submit", { timeout }).catch(catchTimeoutError);
    await page.waitForLoadState("load", { timeout }).catch(catchTimeoutError)
    await takeScreenshot("after_click_submit")
    return waitForResultsList();
  }

  const waitForResultsList = async () => {
    await page.waitForLoadState("load").catch(catchTimeoutError);
    return locators.resultsList.waitFor({ timeout })
      .then(() => sendMessage("ready_for_requests"))
      .catch(catchTimeoutError)

  }

  const connectToSite = async () => {
    const url = BASE_URL + "/catalog?view=list"
    const response = await page.goto(url);
    await takeScreenshot("after_goto_list")
    return continueIfGoodResponse(response, url, signIn);
  }

  const parseJSON = (json) => {
    try {
      return JSON.parse(json)
    } catch (error) {
      return sendErrorMessage({error: "json_parse_error", message: error.message, input: json})
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

    const response = await page.request.get(
      url,
      {
        params: params({
          initialCursorMark: initial_cursor_mark,
          taxonCode: code
        })
      }
    );

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
    const message = buffer.toString().trim()
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