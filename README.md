

# BirdSong

An app to quiz yourself on bird identification by song.

I made this app because I work from home and usually sit on my deck in my backyard when the weather is nice. I hear lots of birds, and I know the usual suspects very well, but every now and then I'll hear one that I don't recognize, and by the time I've run inside to get my Sibley book, they're often gone. I realized that I wanted an easy way to learn the bird songs in my area without putting in hours and hours of field work :sweat_smile:. When I went looking for this, I couldn't find what I wanted, so I figured I had to build it!

The UI is a bit rough at the moment - I am focused more on functionality than looks right now. I'm using a UI framework called [DaisyUI](https://daisyui.com/) that gives me a little bit of style, but I would love to work with a designer at some point to give it some real polish.

## UI Features
- Uses recordings from [Cornell's Macaulay Library ](https://www.macaulaylibrary.org/)
- Enter a specific region to hear birds from (country, state, or county)
- Optionally limit to only certain species groups
- Optionally show images alongside recordings (images are sourced from [flickr.com](https://flickr.com))
- Bird's name is hidden until user clicks to reveal it

## Future Feature ideas
- use browser location
- enable user to change filters from quiz interface
- enable user to input which bird they think it is
- track correct answers in a session
- track correct answers over time
- verbal descriptions of distinguishing physical characteristics
- verbal descriptions of songs & calls
- filter by individual species

## TODO
- [ ] :bangbang: Playwright ports are not getting shutting down on exit
- [ ] use browser location
- [ ] show image attribution
- [ ] filter by recently observed birds
- [ ] filter by recent notable observations in a region
- [ ] enable user to enter any location by text
- [ ] filter by individual species
- [ ] use XC + Ebird for recordings?
- [ ] use Ebird for images? (pro - better images, con - no API)
- [ ] fix broken tests 
  - [ ] `services_test`
  - [ ] `record_data_test`
- [ ] use struct for assigns in LiveView
- [x] show recording attribution
- [x] filter by species group
- [x] enable user to enter any location by code

## Data Features
- Written in Elixir, and uses Phoenix's LiveView framework for the front-end
- Uses ETS tables to cache data
- Uses GenServers to throttle external data requests to no more than 1 request per second
- Uses Playwright (via an Elixir port) to crawl the Macaulay Library site for recordings, since they do not have an API
- Currently writes new JSON responses to .json files and loads them into ETS tables on startup, instead of using a database. My reasoning for this is that I am trying to plan for how to seed the database when I eventually push this to production. There is a LOT of data to seed: 16,847 known species in the world, multiplied by 4 API requests each (1 for images and 3 for recordings). Because requests are rate-limited, it takes hours to collect a full data set, and the collection task often goes down and needs to be restarted. It seems best to write everything to disk for now, but I may change this in the future.

## Running locally

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

The main page is located at [`localhost:4000/quiz`](http://localhost:4000/quiz).
