class Dashing.Simplemon extends Dashing.Widget
  @accessor 'current', Dashing.AnimatedValue

  ready: ->

  onData: (data) ->
    if data.status
      # clear existing "status-*" classes
      $(@get('node')).attr 'class', (i,c) ->
        c.replace /\bstatus-\S+/g, ''
      # add new class
      $(@get('node')).addClass "status-#{data.status}"

    seticon = (id, art) ->
      $(".icon-" + id).remove().after "." + id
      $("<i class=\"icon-" + art + " icon-background icon-" + id + "\"></i>").insertAfter "." + id
      return
    switch data.status
      when "acknowledge"
        seticon data.id, "cog"
      when "normal"
        seticon data.id, "ok"
      when "unknown"
        seticon data.id, "question-sign"
      when "warning"
        seticon data.id, "warning-sign"
      when "danger"
        seticon data.id, "remove"
