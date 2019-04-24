return {
  de = {
    ['ä'] = 'a', -- will be treated as 'a', using letters instead of numbers is preferred
    ['ö'] = 'o',
    ['ü'] = 'u',
     -- s - table that contains all chars, p - current position
    ["ß"] = function(s,p) -- this is how to deal with letter that should be treated as two letters
        table.insert(s, p+1, 's')
        return 115
    end,
    ['Ä'] = 'A', -- will be treated as 'a', using letters instead of numbers is preferred
    ['Ö'] = 'O',
    ['Ü'] = 'U'
  },
  fr = {
    ['à'] = 97.1,
    ['â'] = 97.2,
    ['æ'] = 97.3,
    ['ç'] = 99.1,
    ['é'] = 101.1,
    ['è'] = 101.2,
    ['ê'] = 101.3,
    ['ë'] = 101.4,
    ['î'] = 105.1,
    ['ï'] = 105.2,
    ['ô'] = 111.1,
    ['œ'] = 111.2,
    ['ù'] = 117.1,
    ['û'] = 117.2,
    ['ü'] = 117.3,
    ['ÿ'] = 121.1,				
    ['À'] = 65.1,
    ['Â'] = 65.2,
    ['Æ'] = 65.3,
    ['Ç'] = 67.1,
    ['É'] = 69.1,
    ['È'] = 69.2,
    ['Ê'] = 69.3,
    ['Ë'] = 69.4,
    ['Î'] = 73.1,
    ['Ï'] = 73.2,
    ['Ô'] = 79.1,
    ['Œ'] = 79.2,
    ['Ù'] = 85.1,
    ['Û'] = 85.2,
    ['Ü'] = 85.3,
    ['Ÿ'] = 89.1
  },
  ru = {
    ["ё"] = 1077.1, -- will be placed after 'е'(code 1077)
    ["Ё"] = 1045.1
  },
  tr = {
    ['â'] = 97.1,
    ['ç'] = 99.1,
    ['ğ'] = 103.1,
    ['ı'] = 104.9,
    ['î'] = 105.1,
    ['ö'] = 111.1,
    ['ş'] = 115.1,
    ['ü'] = 117.1,
    ['û'] = 117.2,
    ['Â'] = 65.1,
    ['Ç'] = 67.1,
    ['Ğ'] = 71.1,
    ['I'] = 72.9,
    ['İ'] = 73.1,
    ['Ö'] = 79.1,
    ['Ş'] = 83.1,
    ['Ü'] = 85.1,
    ['Û'] = 85.2
  },
  -- future languages
  pl = {
    ['ą'] = 97.1,
    ['ć'] = 99.1,
    ['ę'] = 101.1,
    ['ł'] = 108.1,
    ['ń'] = 110.1,
    ['ó'] = 111.1,
    ['ś'] = 115.1,
    ['ź'] = 122.1,
    ['ż'] = 122.2,
    ['Ą'] = 65.1,
    ['Ć'] = 67.1,
    ['Ę'] = 69.1,
    ['Ł'] = 76.1,
    ['Ń'] = 78.1,
    ['Ó'] = 79.1,
    ['Ś'] = 83.1,
    ['Ź'] = 90.1,
    ['Ż'] = 90.2
  },
  nl = {
    ['i'] = function(s,p) -- this is how to treat digraphs ('ij' should be treated as one letter)
        if s[p+1] == 'j' then
            table.remove(s, p+1)
            return 121.1
        end
        return 'i'
    end,
    ['I'] = function(s,p)
        if s[p+1] == 'J' then
            table.remove(s, p+1)
            return 89.1
        end
        return 'I'
    end
  },
  es = {
    ['ñ'] = 110.1,
    ['Ñ'] = 78.1
  }
}