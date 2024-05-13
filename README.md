Для можливості завантаження обмежених репозиторіїв треба додати token для сайту huggingface.co, для чого змінити файл `./scripts/setup`:<br />
змінити рядок: "from huggingface_hub import hf_hub_download, snapshot_download",<br />
додати імпорт "login", щоб вийшло таким чином:<br />
"from huggingface_hub import hf_hub_download, snapshot_download, login"<br />
Потім, всередині "if __name__ == '__main__':" додати реєстрацію на сайті:<br />
"login(token='my_token')", де 'my_token' змінити на свій токен доступу на сайт https://huggingface.co<br /><br />
Для збільшення буферу пам'яті для чат-двигуна треба змінити файл `./private_gpt/server/chat/chat_service.py`:

    from llama_index.core.memory import ChatMemoryBuffer   # 🔴red=31<-- ADD IMPORT;

    def _chat_engine(
        self,
        system_prompt: str | None = None,
        use_context: bool = False,
        context_filter: ContextFilter | None = None,
    ) -> BaseChatEngine:
        if use_context:
            vector_index_retriever = self.vector_store_component.get_retriever(
                index=self.index, context_filter=context_filter
            )
            memory = ChatMemoryBuffer.from_defaults(token_limit=8192)  # <-- MORE TOKENS
            return ContextChatEngine.from_defaults(
                system_prompt=system_prompt,
                retriever=vector_index_retriever,
                memory=memory,  #  <-- USE THE  LARGER BUFFER
                llm=self.llm_component.llm,
                node_postprocessors=[
                    MetadataReplacementPostProcessor(target_metadata_key="window"),
                ],
            )
