#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.  The
# ASF licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations
# under the License.

class String

  # Rails defines this for a number of other classes, including Object
  # see activesupport/lib/active_support/core_ext/object/blank.rb
  unless method_defined? 'blank?'
    def blank?
      self !~ /\S/
    end
  end

  # Title case.
  #
  #   "this is a string".titlecase
  #   => "This Is A String"
  #
  # CREDIT: Eliazar Parra
  # Copied from facets
  unless method_defined? 'titlecase'
    def titlecase
      gsub(/\b\w/){ $`[-1,1] == "'" ? $& : $&.upcase }
    end
  end

  unless method_defined? 'pluralize'
    def pluralize
      return self + 'es' if self =~ /ess$/
      return self[0, self.length-1] + "ies" if self =~ /ty$/
      return self if self =~ /data$/
      self + "s"
    end
  end

  unless method_defined? 'singularize'
    def singularize
      return self.gsub(/ies$/, 'y') if self =~ /ies$/
      return self.gsub(/es$/, '') if self =~ /sses$/
      self.gsub(/s$/, '')
    end
  end

  unless method_defined? 'underscore'
    def underscore
      gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
    end
  end

  unless method_defined? 'camelize'
    def camelize(lowercase_first_letter=nil)
      s = split('_').map { |w| w.capitalize }.join
      lowercase_first_letter ? s.uncapitalize : s
    end
  end

  unless method_defined? 'uncapitalize'
    def uncapitalize
      self[0, 1].downcase + self[1..-1]
    end
  end

  def upcase_first
    self[0, 1].upcase + self[1..-1]
  end

  unless method_defined? 'truncate'
    def truncate(length = 10)
      return self if self.length <= length
      end_string = "...#{self[(self.length-(length/2))..self.length]}"
      "#{self[0..(length/2)]}#{end_string}"
    end
  end

  def remove_matrix_params
    self.gsub(/;([^\/]*)/, '').gsub(/\?(.*)$/, '')
  end

  def convert_query_params(params={})
    gsub(/:(\w+)/) { |p| params.delete(p[1..-1].to_sym) } +
      params.to_query_params
  end

  unless "".respond_to? :each
    alias :each :each_line
  end

end
