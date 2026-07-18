
from pathlib import Path


def readFileAndFolder():
    path = Path("")
    items = list(path.rglob("*"))
    for i, item in enumerate(items):
     print(f"{i+1}. {item}")


def createFile():
    try:
        readFileAndFolder()
        name = input("Enter the name of the file to create: ")
        p = Path(name)
        if not p.exists():
            with p.open("w") as f:
                data = input("Enter the content of the file: ")
                f.write(data)
            print(f"File {name} created successfully.")
        else:
            print(f"File {name} already exists.")
    except Exception as e:
        print(f"Error creating file: {e}")

def readFile():
    try:
        readFileAndFolder()
        name = input("Enter the name of the file to read: ")
        p = Path(name)
        if p.exists() and p.is_file():
            with p.open("r") as f:
                data = f.read()
                print(f"Content of {name}: {data}")
        else:
            print(f"File {name} does not exist.")
    except Exception as e:
        print(f"Error reading file: {e}")

def updateFile():
    try:
        readFileAndFolder()
        name = input("Enter the name of the file to update: ")
        p = Path(name)
        if p.exists() and p.is_file():
            print("press 1 for changing the file name")
            print("press 2 for changing the file content")
            print ("press 3 for appending the file content")

            choice = int(input("Enter your choice: "))
            if choice == 1:
                new_name = input("Enter the new name of the file: ")
                p.rename(new_name)
                print(f"File renamed to {new_name}.")
            elif choice == 2:
                new_content = input("Enter the new content of the file: ")
                with p.open("w") as f:
                    f.write(new_content)
                print(f"Content of {name} updated successfully.")
            elif choice == 3:
                append_content = input("Enter the content to append to the file: ")
                with p.open("a") as f:
                    f.write(append_content)
                print(f"Content appended to {name} successfully.")
            else:
                print("Invalid choice.")
        else:
            print(f"File {name} does not exist.")
    except Exception as e:
        print(f"Error updating file: {e}")

def deleteFile():
    try:
        readFileAndFolder()
        name = input("Enter the name of the file to delete: ")
        p = Path(name)
        if p.exists() and p.is_file():
            p.unlink()
            print(f"File {name} deleted successfully.")
        else:
            print(f"File {name} does not exist.")
    except Exception as e:
        print(f"Error deleting file: {e}")
print("Press 1 for the creating the file")
print("Press 2 to reading the file")
print("Press 3 to updating the file")
print("Press 4 to deleting the file")


check = int(input("Enter your choice: "))
if check == 1:
    createFile()
if check == 2:
    readFile()   
if check == 3:
    updateFile()
if check == 4:
    deleteFile() 
