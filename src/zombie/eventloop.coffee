URL = require("url")


# Handles the Window event loop, timers and pending requests.
class EventLoop
  constructor: (browser)->
    timers = {}
    lastHandle = 0

    # ### window.setTimeout(fn, delay) => Number
    #
    # Implements window.setTimeout using event queue
    this.setTimeout = (fn, delay)->
      timer = 
        when: browser.clock + delay
        timeout: true
        fire: =>
          try
            if typeof fn == "function"
              fn.apply this
            else
              eval fn
          finally
            delete timers[handle]
      handle = ++lastHandle
      timers[handle] = timer
      handle

    # ### window.setInterval(fn, delay) => Number
    #
    # Implements window.setInterval using event queue
    this.setInterval = (fn, delay)->
      timer = 
        when: browser.clock + delay
        interval: true
        fire: =>
          try
            if typeof fn == "function"
              fn.apply this
            else
              eval fn
          finally
            timer.when = browser.clock + delay
      handle = ++lastHandle
      timers[handle] = timer
      handle

    # ### window.clearTimeout(timeout)
    #
    # Implements window.clearTimeout using event queue
    this.clearTimeout = (handle)-> delete timers[handle] if timers[handle]?.timeout
    # ### window.clearInterval(interval)
    #
    # Implements window.clearInterval using event queue
    this.clearInterval = (handle)-> delete timers[handle] if timers[handle]?.interval

    # Size of processing queue (number of ongoing tasks).
    processing = 0
    # Requests on wait that cannot be handled yet: there's no event in the
    # queue, but we anticipate one (in-progress XHR request).
    waiting = []
    # Called when done processing a request, and if we're done processing all
    # requests, wake up any waiting callbacks.
    wakeUp = ->
      if --processing == 0
        process.nextTick waiter while waiter = waiting.pop()

    # ### perform(fn)
    #
    # Run the function as part of the event queue (calls to `wait` will wait for
    # this function to complete).  Function can be anything and is called
    # synchronous with a `done` function; when it's done processing, it lets the
    # event loop know by calling the done function.
    this.perform = (fn)->
      ++processing
      fn wakeUp
      return

    # ### wait(window, terminate, callback, intervals)
    #
    # Process all events from the queue. This method returns immediately, events
    # are processed in the background. When all events are exhausted, it calls
    # the callback with null, window; if any event fails, it calls the callback
    # with the exception.
    #
    # Events include timeout, interval and XHR onreadystatechange. DOM events
    # are handled synchronously.
    this.wait = (window, terminate, callback, intervals)->
      process.nextTick =>
        earliest = null
        for handle, timer of timers
          continue if timer.interval && intervals == false
          earliest = timer if !earliest || timer.when < earliest.when
        if earliest
          intervals = false
          event = ->
            browser.clock = earliest.when if browser.clock < earliest.when
            earliest.fire()
        if event
          try 
            event()
            done = false
            if typeof terminate is "number"
              --terminate
              done = true if terminate <= 0
            else if typeof terminate is "function"
              done = true if terminate.call(window) == false
            if done
              process.nextTick ->
                browser.emit "done", browser
                callback null, window if callback
            else
              @wait window, terminate, callback, intervals
          catch err
            browser.emit "error", err
            callback err, window if callback
        else if processing > 0
          waiting.push => @wait window, terminate, callback, intervals
        else
          browser.emit "done", browser
          callback null, window if callback

    # Used internally for the duration of an internal request (loading
    # resource, XHR). Also collects request/response for debugging.
    #
    # Function is called with request object and the function to be called
    # next. After storing the request, that function is called with a single
    # argument, a done callback. It must call the done callback when it
    # completes processing, passing error and response arguments.
    #
    # See also `processing`.
    this.request = (request, fn)->
      url = request.url.toString()
      browser.log -> "#{request.method} #{url}"
      pending = browser.record request
      ++processing
      fn (err, response)->
        if err
          browser.log -> "Error loading #{url}: #{err}"
          pending.error = err
        else
          browser.log -> "#{request.method} #{url} => #{response.status}"
          pending.response = response
        wakeUp()

    this.extend = (window)=>
      for fn in ["setTimeout", "setInterval", "clearTimeout", "clearInterval"]
        window[fn] = this[fn]
      window.perform = this.perform
      window.wait = (terminate, callback)=> this.wait(window, terminate, callback)
      window.request = this.request 

    this.dump = ()->
      [ "The time:   #{browser.clock}",
         "Timers:     #{timers.length}",
         "Processing: #{processing}",
         "Waiting:    #{waiting.length}" ]

exports.use = (browser)->
  return new EventLoop(browser)
