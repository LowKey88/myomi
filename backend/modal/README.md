Install and log in via the Modal CLI (if not done already): 
no need for now you can simply use docker  compose to run the project in backend folder

```bash
pip install modal-client
modal login
```

Then, you can run the following command to create a new project:

```bash
cd modal
modal secret create huggingface-token  HUGGINGFACE_TOKEN=hf_token
modal deploy main.py
```

