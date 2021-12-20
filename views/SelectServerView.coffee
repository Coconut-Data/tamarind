Backbone = require 'backbone'

class SelectServerView extends Backbone.View

  render: =>
    @$el.html "
    <iframe class='help' style='display:none; float:right' width='420' height='315' src='https://www.youtube.com/embed/ai3ZsBCGlD4'></iframe>
      <h1>Select a Database Server</h1>
      <table>
        <thead>
        </thead>
        <tbody>
        #{
          (for name, url of Tamarind.knownDatabaseServers
            "
            <tr style='height:50px;'>
              <td><a href='#server/#{name}'>#{name}</a></td>
              <td><a href='#server/#{name}'>#{url}</a></td>
            </tr>
            "
          ).join("")
        }
        </tbody>
      </table>
    "

module.exports = SelectServerView
