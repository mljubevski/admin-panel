import Foundation
import Leaf
import Node
import Vapor

public class FormNumberGroup: BasicTag {
    public init(){}
    public let name = "form:numbergroup"
    
    public func run(arguments: ArgumentList) throws -> Node? {
        
        /*
         #form:numbergroup(key, value, fieldset)
         
         Arguments:
         [0] = The name of the input (the key that gets posted) *
         [1] = The value of the input (the value that gets posted) (defaults to empty string) *
         [2] = The VaporForms Fieldset of the entire model * **
         
         * - All the arguments are actually required. We need to throw exceptions at people if they don't supply all of them
         ** - It would be awesome if you could only post the exact Field of the Fieldset so we don't need to find it in this code (its gonna get repetetive)
         
         The <label> will get its value from the Fieldset
         
         If the Fieldset has the "errors" property the form-group will get the has-error css class and all errors will be added as help-block's to the form-group
         
         given input:
         
         let fieldset = Fieldset([
            "age": IntegerField(
                label: "Your Age",
                Int.MinimumValidator(value: 1),
                Int.MaximumValidator(value: 110)
            )
         ], requiring: ["age"])
         
         #form:numbergroup("age", 10, fieldset)
         
         expected output if fieldset is valid:
         <div class="form-group">
            <label class="control-label" for="age">Your Age</label>
            <input class="form-control" type="number" id="age" name="age" value="10" />
         </div>
         
         expected output if fieldset is invalid:
         <div class="form-group has-error">
            <label class="control-label" for="age">Your Age</label>
            <input class="form-control" type="number" id="age" name="age" value="10" />
            <span class="help-block">...validation message N</span>
         </div>
         */
        
        
        guard arguments.count >= 3,
            let inputName: String = arguments.list[0].value(with: arguments.stem, in: arguments.context)?.string,
            let fieldsetNode = arguments.list[2].value(with: arguments.stem, in: arguments.context)
            else {
                throw Abort.serverError
        }
        
        var inputValue:Any
        
        //TODO Does this use fieldset?["value"]?.string ???
        if(arguments.list[1].value(with: arguments.stem, in: arguments.context)?.int != nil) {
            inputValue = arguments.list[1].value(with: arguments.stem, in: arguments.context)?.int as Any
        } else if(arguments.list[1].value(with: arguments.stem, in: arguments.context)?.float != nil) {
            inputValue = Float((arguments.list[1].value(with: arguments.stem, in: arguments.context)?.float!)!)
        } else {
            inputValue = ""
        }
        
        let fieldset = fieldsetNode[inputName]
        
        let label = fieldset?["label"]?.string ?? inputName
        
        // This is not a required property
        let errors = fieldset?["errors"]?.pathIndexableArray
        
        // Start constructing the template
        var template = [String]()
        
        template.append("<div class='form-group \(errors != nil ? "has-error" : "")'>")
        
        template.append("<label class='control-label' for='\(inputName)'>\(label)</label>")
        
        template.append("<input class='form-control' type='number' id='\(inputName)' name='\(inputName)' value='\(inputValue)' ")
        
        // Add custom attributes
        if arguments.count > 3 {
            let max = arguments.count - 1
            for index in 3 ... max {
                if let argument = arguments.list[index].value(with: arguments.stem, in: arguments.context)?.string {
                    template.append(" " + argument)
                }
            }
        }
        
        template.append("/>")
        
        // If Fieldset has errors then loop through them and add help-blocks
        if(errors != nil) {
            for e in errors! {
                
                guard let errorString = e.string else {
                    continue
                }
                
                template.append("<span class='help-block'>\(errorString)</span>")
            }
        }
        
        template.append("</div>")
        
        // Return template
        return .bytes(template.joined().bytes)
    }
}
