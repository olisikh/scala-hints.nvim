local logger = require('scala-hints.logger')

describe('logger', function()
  it('includes file name when provided', function()
    local log = logger.new('logger_spec')
    local file = 'MapSmells.scala'
    log.info('test message', { file = file })

    local path = string.format('/tmp/scala-hints/log/%s.log', os.date('%Y-%m-%d'))
    local fh = io.open(path, 'r')
    assert.is_truthy(fh)

    local content = fh:read('*a')
    fh:close()

    assert.is_truthy(string.find(content, 'file=' .. file, 1, true))
  end)
end)
