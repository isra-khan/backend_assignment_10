class Animal:
    name = "Animal"
    def __init__(self,age):
        self.age = age

    def show(self):
        print(f"Name: {self.name}, Age: {self.age}")

    @classmethod
    def class_method(cls):
        print(f"This is a class method of {cls.__name__}")

    @staticmethod
    def static_method():
        print("This is a static method.")




obj = Animal(5)
obj.show()
Animal.class_method()
Animal.static_method()