This is a neovim plugin that will work like this:                                                                                    
- A user runs a command n00bkeys                                                                                                                                         
- This pops up a small text box like WhichKeys or cmdline (I'm using LazyVim) except multi-row, like a textarea in html                                                  
- A user types a query like "how do I switch focus to the project pane?" or any other random question about how to use neovim                                            
- The plugin makes a call to OpenAI's API.  For now, assume the key is provided by an env var OPENAI_API_KEY or a .env file with OPENAI_API_KEY defined                  
- The user's provided prompt is augmented with information like: the version of neovim the user is using, any 'distro'/'starter pack' like LazyVim, etc, a list of the   
enabled plugins, and context around what the prompt is for (The user is asking for instructions on which keys to press to perform an action in neovim) and how the       
response should be structured (a concise, practical explanation of how to perform that action in neovim, or if the prompt is unclear, a minimal suggestion on how to     
clarify the prompt).  Do not clear the prompt after it has been submitted.  DO show a spinner or some other indication that the request is being processed.  DO have a   
way of indicating to the user that an error occurred with a CLEAR error message WITHOUT clearing the prompt.                                                             
- There should be key bindings for the following:                                                                                                                        
  - Clear the prompt and focus the promnpt text box                                                                                                                      
  - Focus the textbox so the user can edit the prompt and resubmit                                                                                                       
  - Submit the prompt in the text box (enter/return)                                                                                                                     
  - Apply the LLM's suggested edit (if multiple suggestions, allow choosing one to replace the prompt in the box) to the text box and focus for editing
