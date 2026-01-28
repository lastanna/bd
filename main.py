import os
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import psycopg2  # или asyncpg для асинхронности

app = FastAPI()


class OrderItemRequest(BaseModel):
    order_id: int
    goods_id: int
    quantity: int


@app.post("/order/add-item")
def add_item(item: OrderItemRequest):
    # Загружаем переменные из .env
    load_dotenv()

    # Формируем строку подключения, используя переменные из .env
    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "db"),  # "db" — значение по умолчанию
        database=os.getenv("POSTGRES_DB"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD")
    )
    cur = conn.cursor()

    try:
        # Вызываем нашу процедуру
        cur.execute("CALL add_item_to_order(%s, %s, %s)",
                    (item.order_id, item.goods_id, item.quantity))
        conn.commit()
        return {"status": "success", "message": "Товар добавлен в заказ"}

    except Exception as e:
        conn.rollback()
        # Если база выбросила RAISE EXCEPTION, прокидываем её в API
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        cur.close()
        conn.close()
