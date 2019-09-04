require "nested_form_fields/version"

module NestedFormFields
  module Rails
    class Engine < ::Rails::Engine
    end
  end
end

module ActionView::Helpers

  class FormBuilder

    # options:
    #   include_template
    #   custom_object_name
    #   template_only
    #   start_index
    def nested_fields_for(record_name, record_object = nil, fields_options = {}, &block)
      
      fields_options, record_object = record_object, nil if record_object.is_a?(Hash) && record_object.extractable_options?
      fields_options[:builder] ||= options[:builder]
      fields_options[:parent_builder] = self
      fields_options[:wrapper_tag] ||= :fieldset
      fields_options[:wrapper_options] ||= {}
      fields_options[:namespace] = fields_options[:parent_builder].options[:namespace]

      # custom
      # replaces __nested_field_for_replace_with_index__ inside block with index
      
      options[:start_index]         # start index for __nested_field_for_replace_with_index__ substitution
      options[:child_index]         # start index for children
      options[:custom_object_name]  # custom name instead of object_name from parent form builder object
      options[:include_template]    # render template
      options[:template_only]       # render only template

      # output = ActiveSupport::SafeBuffer.new
      # output << @template.content_tag("")
      
      return fields_for_has_many_association_with_template(record_name, record_object, fields_options, block)
    end

    def add_nested_fields_link association, text = nil, html_options = {}, &block
      html_options, text = text, nil if block_given? && text.is_a?(Hash)
      html_class = html_options.delete(:class) || {}
      html_data = html_options.delete(:data) || {}

      args = []
      args << (text || "Add #{association.to_s.singularize.humanize}") unless block_given?
      args << ''
      args << { class: "#{html_class.empty? ? '' : html_class} add_nested_fields_link",
                data: { association_path: association_path(association.to_s),
                        object_class: association.to_s.singularize }.merge(html_data)
              }.merge(html_options)

      @template.link_to *args, &block
    end

    def remove_nested_fields_link text = nil, html_options = {}, &block
      html_options, text = text, nil if block_given? && text.is_a?(Hash)
      html_class = html_options.delete(:class) || {}
      html_data = html_options.delete(:data) || {}

      args = []
      args << (text || 'x') unless block_given?
      args << ''
      args << { class: "#{html_class.empty? ? '' : html_class} remove_nested_fields_link",
                data: { delete_association_field_name: delete_association_field_name,
                        object_class: @object.class.name.underscore.downcase }.merge(html_data)
              }.merge(html_options)

      @template.link_to *args, &block
    end

    private

    def fields_for_has_many_association_with_template(association_name, association, options, block)

      # TODO: legend
      name = "#{options[:custom_object_name].clone || object_name}[#{association_name}_attributes]"

      ## File actionpack/lib/action_view/helpers/form_helper.rb, line 109
      # def convert_to_model(object)
      #   object.respond_to?(:to_model) ? object.to_model : object
      # end
      association = convert_to_model(association) # returns object for openstruct

      # TODO: handle all relevant cases
      # model, openstruct
      # collections
      # nil

      # true for single model instance, should serve the same purpose as reflect on all associations
      if association.respond_to?(:persisted?) || association.is_a?(OpenStruct)  
        association = [association]
      elsif not association.respond_to?(:to_ary)    # if it does not respond to to_ary
        association = @object.send(association_name) # probably needs to go if single or openstruct, seems wrong in above case
        # .respond_to?(:reflect_on_all_associations)
      end

      Rails.logger.tagged("Fatality") {
        Rails.logger.fatal "begin" 
        Rails.logger.fatal "object_name: #{object_name}" # delivery_order
        Rails.logger.fatal "custom_object_name: #{options[:custom_object_name].clone}"
        Rails.logger.fatal "name: #{name}"               # see above
        Rails.logger.fatal "object: #{object}"           # @delivery_order
        Rails.logger.fatal "association_name: #{association_name}"  # custom string should probably be just the name, custom_string should become the object_name?
        Rails.logger.fatal "association: #{association}"            # docp.first
        Rails.logger.fatal "include_template: #{options[:include_template]}"
        Rails.logger.fatal "end"
      }

      output = ActiveSupport::SafeBuffer.new
      unless options[:template_only] 
        association.each_with_index do |child, index|
          index += options[:start_index].to_i # start_index, zero if nil
          # TODO: nested child index
          Rails.logger.tagged("start_index") { Rails.logger.fatal options[:start_index] }
          wrapper_options = options[:wrapper_options].clone || {}
          if child._destroy == true # works for openstruct too
            wrapper_options[:style] = wrapper_options[:style] ? wrapper_options[:style] + ';' + 'display:none' : 'display:none'
            output << destroy_hidden_field(association_name, index)
          end
          
          wtf = 7
          # Build the wrapper + content and do substitution with the current index allows JS functions to have proper references
          wrapped_block = nested_fields_wrapper(association_name, options[:wrapper_tag], options[:legend], wrapper_options) do
            fields_for_nested_model("#{name}[#{nested_child_index(name) + options[:child_index].to_i}]", child, options, block)
          end
          output << wrapped_block.gsub('__nested_field_for_replace_with_index__', index.to_s).html_safe
        end
      end
      output << nested_model_template(name, association_name, options, block) unless options[:include_template] == false
      return output
    end

    def nested_model_template name, association_name, options, block
      for_template = self.options[:for_template]

      # Render the outermost template in a script tag to avoid it from being submited with the form
      # Render all deeper nested templates as hidden divs as nesting script tags messes up the html.
      # When nested fields are added with javascript by using a template that contains nested templates,
      # the outermost nested templates div's are replaced by script tags to prevent those nested templates
      # fields from form subission.
      #
      @template.content_tag( for_template ? :div : :script,
                             type: for_template ? nil : 'text/html',
                             id: template_id(association_name),
                             class: for_template ? 'form_template' : nil,
                             style: for_template ? 'display:none' : nil ) do
        nested_fields_wrapper(association_name, options[:wrapper_tag], options[:legend], options[:wrapper_options]) do
          # class name
          association_class = (options[:class_name] || @object.public_send(association_name).klass.name).to_s.classify.constantize
          fields_for_nested_model("#{name}[#{index_placeholder(association_name)}]", association_class.new, options.merge(for_template: true), block)
        end
      end
    end

    def template_id association_name
      "#{association_path(association_name)}_template"
    end

    def association_path association_name
      "#{(options[:custom_object_name].clone || object_name).to_s.gsub('][','_').gsub(/_attributes/,'').sub('[','_').sub(']','')}_#{association_name}"
    end

    def index_placeholder association_name
      "__#{association_path(association_name)}_index__"
    end

    def delete_association_field_name
      "#{options[:custom_object_name].clone || object_name}[_destroy]"
    end

    def nested_fields_wrapper(association_name, wrapper_element_type, legend, wrapper_options)

      wrapper_options = add_default_classes_to_wrapper_options(association_name, wrapper_options.clone)

      @template.content_tag wrapper_element_type, wrapper_options do
        (wrapper_element_type == :fieldset && !legend.nil?)? ( @template.content_tag(:legend, legend, class: "nested_fields") + yield ) : yield
      end

    end

    def destroy_hidden_field(association_name, index)
      @template.hidden_field "#{options[:custom_object_name].clone || object_name}[#{association_name}_attributes][#{index}]",
                             :_destroy, value: 1
    end

    def add_default_classes_to_wrapper_options(association_name, wrapper_options)
      default_classes = ["nested_fields", "nested_#{association_path(association_name)}"]
      wrapper_options[:class] = wrapper_options[:class].is_a?(String) ? wrapper_options[:class].split(" ") : wrapper_options[:class].to_a
      wrapper_options[:class] += default_classes
      wrapper_options
    end
  end
end
